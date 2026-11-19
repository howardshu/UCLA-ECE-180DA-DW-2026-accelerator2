// Fully connected layer + argmax.
//
//   logit[o] = bias[o] + sum_{i<48} p2[i] * wgt[WGT_FC_BASE + o*48 + i]   (int32)
//   RES[o]   = logit[o]                     for o = 0..9
//   RES[10]  = index of the largest logit. The first (lowest-index) maximum
//              wins: a team assumption until the course confirms the tie rule.
//
// p2 is in ACT_B[0..47] (uint8, flattened HWC, which is exactly the fc input
// order). No shift and no ReLU on the logits. RES[11] (MAGIC) is left to the
// controller, which writes it after done_o.
//
// Schedule. One PE, one MAC per cycle: WGT returns one byte per cycle, so more
// PEs would not help. Reads for all ten neurons issue back to back (480
// cycles). The input index is kept as (pix, ch) counters so a packed ACT_B can
// later use pix as the word address and ch as the lane, with no divider.
//
// Each read's control (first, last, neuron) travels through an RD_LAT-deep
// pipe so it meets its returned data. pe_top's sum_o is the accumulator
// register, so a neuron's logit is valid only in the cycle after the edge that
// accepts its 48th product. That cycle writes RES[wr_idx] and updates the
// running argmax, while the PE already accepts the next neuron's first
// product. wr_idx is captured on the last-product edge because the return
// pipe may already hold the next neuron by then.
//
// Handshake: start_i is a one-cycle pulse; done_o is a one-cycle pulse in the
// cycle after RES[10] is written.

module acc_fc
    import accelerator_cnn_pkg::*;
    import acc_internal_pkg::*;
#(
    parameter int unsigned RD_LAT = 1   // read latency of the src and wgt ports
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,

    input  logic                   start_i,
    output logic                   done_o,

    input  acc_t                   cfg_bias_i [FC_O],

    // Flattened p2 (ACT_B)
    output logic [BYTE_ADDR_W-1:0] src_addr_o,
    input  act_t                   src_rdata_i,

    // Weights (WGT)
    output logic [WGT_ADDR_W-1:0]  wgt_addr_o,
    input  wgt_t                   wgt_rdata_i,

    // Results (RES words 0..10)
    output logic                   res_we_o,
    output logic [RES_ADDR_W-1:0]  res_addr_o,
    output logic [31:0]            res_wdata_o
);

    localparam int unsigned N_PIX = P2_H * P2_W;   // 16 pooled pixels
    localparam int unsigned N_CH  = C2_OC;         //  3 channels per pixel

    if (RD_LAT < 1) begin : g_bad_rd_lat
        $error("acc_fc: RD_LAT must be at least 1");
    end
    if (N_PIX * N_CH != FLAT) begin : g_bad_flat
        $error("acc_fc: P2_H*P2_W*C2_OC must equal FLAT");
    end

    // Control that travels with each read until its data returns.
    typedef struct packed {
        logic       valid;
        logic       first;   // first product of a neuron: start from its bias
        logic       last;    // last product of a neuron
        logic [3:0] o;       // neuron index
    } md_t;


    // ----- Issue stage -----
    logic       issuing;
    logic [3:0] o_q;
    logic [3:0] pix_q;
    logic [1:0] ch_q;
    logic [5:0] idx;         // pix*3 + ch: flattened p2 index, 0..47
    md_t        issue_md;

    assign idx        = 6'(pix_q) * 6'(N_CH) + 6'(ch_q);
    assign src_addr_o = BYTE_ADDR_W'(idx);
    assign wgt_addr_o = WGT_ADDR_W'(WGT_FC_BASE) + WGT_ADDR_W'(o_q) * WGT_ADDR_W'(FLAT)
                      + WGT_ADDR_W'(idx);

    assign issue_md.valid = issuing;
    assign issue_md.first = (pix_q == '0) && (ch_q == '0);
    assign issue_md.last  = (pix_q == 4'(N_PIX - 1)) && (ch_q == 2'(N_CH - 1));
    assign issue_md.o     = o_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            issuing <= 1'b0;
            o_q     <= '0;
            pix_q   <= '0;
            ch_q    <= '0;
        end else if (start_i) begin
            issuing <= 1'b1;
            o_q     <= '0;
            pix_q   <= '0;
            ch_q    <= '0;
        end else if (issuing) begin
            if (ch_q == 2'(N_CH - 1)) begin
                ch_q <= '0;
                if (pix_q == 4'(N_PIX - 1)) begin
                    pix_q <= '0;
                    if (o_q == 4'(FC_O - 1)) issuing <= 1'b0;
                    else                     o_q     <= o_q + 1'b1;
                end else begin
                    pix_q <= pix_q + 1'b1;
                end
            end else begin
                ch_q <= ch_q + 1'b1;
            end
        end
    end


    // ----- Return stage: control delayed by the read latency -----
    md_t md_q [RD_LAT];
    md_t ret;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < int'(RD_LAT); i++) md_q[i] <= '0;
        end else begin
            md_q[0] <= issue_md;
            for (int i = 1; i < int'(RD_LAT); i++) md_q[i] <= md_q[i-1];
        end
    end

    assign ret = md_q[RD_LAT-1];


    // ----- MAC -----
    acc_t sum;
    // verilator lint_off UNUSEDSIGNAL
    act_t requant_unused;   // conv-only output; logits are not requantized
    // verilator lint_on UNUSEDSIGNAL

    pe_top u_pe (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .clear_i     (1'b0),
        .valid_i     (ret.valid),
        .first_mac_i (ret.first),
        .act_i       (src_rdata_i),
        .wgt_i       (wgt_rdata_i),
        .bias_i      (cfg_bias_i[ret.o]),
        .shift_i     ('0),
        .sum_o       (sum),
        .requant_o   (requant_unused)
    );


    // ----- Logit write, running argmax, completion -----
    logic       wr_pending;   // sum holds neuron wr_idx's complete logit
    logic [3:0] wr_idx;
    acc_t       best;
    logic [3:0] best_idx;
    logic       am_pending;   // write RES[10] this cycle

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_pending <= 1'b0;
            wr_idx     <= '0;
            best       <= '0;
            best_idx   <= '0;
            am_pending <= 1'b0;
            done_o     <= 1'b0;
        end else begin
            wr_pending <= ret.valid && ret.last;
            if (ret.valid && ret.last) wr_idx <= ret.o;

            // Signed compare; strict > keeps the first maximum on a tie.
            if (wr_pending && (wr_idx == '0 || sum > best)) begin
                best     <= sum;
                best_idx <= wr_idx;
            end

            am_pending <= wr_pending && (wr_idx == 4'(FC_O - 1));
            done_o     <= am_pending;
        end
    end

    assign res_we_o    = wr_pending || am_pending;
    assign res_addr_o  = am_pending ? RES_ADDR_W'(RES_ARGMAX) : RES_ADDR_W'(wr_idx);
    assign res_wdata_o = am_pending ? 32'(best_idx) : sum;

endmodule
