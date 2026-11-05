// Three output-channel PEs with a broadcast activation and local weight banks.
// Config is stable until done. Read responses have exactly one cycle latency.
// Weights are preloaded once per layer. Compute accepts one input per cycle;
// the three completed output channels are serialized onto the byte write port.
module acc_conv
    import accelerator_cnn_pkg::*;
    import acc_internal_pkg::*;
(
    input  logic                   clk_i,
    input  logic                   rst_ni,

    input  logic                   start_i,
    output logic                   done_o,

    // Layer configuration
    input  logic [4:0]             cfg_in_hw_i,      // 28 or 12
    input  logic [1:0]             cfg_in_c_i,       // 1 or 3
    input  logic [BYTE_ADDR_W-1:0] cfg_src_base_i,   // image offset for conv1
    input  logic [WGT_ADDR_W-1:0]  cfg_wgt_base_i,
    input  logic [4:0]             cfg_shift_i,
    input  acc_t                   cfg_bias_i [NUM_PE],

    // Input activations (IMG or ACT_B)
    output logic [BYTE_ADDR_W-1:0] src_addr_o,
    input  act_t                   src_rdata_i,

    // Weights (WGT)
    output logic [WGT_ADDR_W-1:0]  wgt_addr_o,
    input  wgt_t                   wgt_rdata_i,

    // Output activations (ACT_A)
    output logic                   dst_we_o,
    output logic [BYTE_ADDR_W-1:0] dst_addr_o,
    output act_t                   dst_wdata_o
);

    typedef enum logic [2:0] {IDLE, LOAD, RUN, WRITE, FINISH} state_t;
    state_t state;
    wgt_t weight_bank [NUM_PE][75]; // 25 taps/channel * at most 3 input channels
    act_t pe_result [NUM_PE];
    int unsigned taps, total_weights, out_hw;
    int unsigned load_req, load_slot, load_channel, load_tap;
    logic load_pending;
    int unsigned h, w, r, s, c, issue_tap, return_tap, write_channel;
    logic operand_pending, issued_all;

    assign taps = 25 * int'(cfg_in_c_i);
    assign total_weights = NUM_PE * taps;
    assign out_hw = int'(cfg_in_hw_i) - 4;
    assign wgt_addr_o = WGT_ADDR_W'(int'(cfg_wgt_base_i) +
                                  (load_req < total_weights ? load_req : 0));
    assign src_addr_o = BYTE_ADDR_W'(int'(cfg_src_base_i) +
        (((h+r)*int'(cfg_in_hw_i) + w+s)*int'(cfg_in_c_i) + c));
    assign dst_we_o = rst_ni && state == WRITE;
    assign dst_addr_o = BYTE_ADDR_W'((h*out_hw+w)*NUM_PE + write_channel);
    assign dst_wdata_o = pe_result[write_channel];
    assign done_o = state == FINISH;

    for (genvar o=0; o<NUM_PE; o++) begin : g_pe
        pe_top u_pe (
            .clk_i(clk_i), .rst_ni(rst_ni), .clear_i(1'b0),
            .valid_i(state == RUN && operand_pending),
            .first_mac_i(return_tap == 0), .act_i(src_rdata_i),
            .wgt_i(weight_bank[o][return_tap]), .bias_i(cfg_bias_i[o]),
            .shift_i(cfg_shift_i), .sum_o(), .requant_o(pe_result[o])
        );
    end

    // Issue address/counters and remember the tap for the following response.
    // The final response updates all PEs before WRITE exposes their results.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            load_req <= 0; load_slot <= 0; load_pending <= 0;
            load_channel <= 0; load_tap <= 0;
            h <= 0; w <= 0; r <= 0; s <= 0; c <= 0;
            issue_tap <= 0; return_tap <= 0; write_channel <= 0;
            operand_pending <= 0; issued_all <= 0;
        end else begin
            case (state)
                IDLE: if (start_i) begin
                    load_req <= 0; load_slot <= 0; load_pending <= 0;
                    load_channel <= 0; load_tap <= 0;
                    h <= 0; w <= 0; r <= 0; s <= 0; c <= 0;
                    issue_tap <= 0; return_tap <= 0; write_channel <= 0;
                    operand_pending <= 0; issued_all <= 0;
                    state <= LOAD;
                end
                LOAD: begin
                    load_pending <= load_req < total_weights;
                    if (load_req < total_weights) begin
                        load_slot <= load_req;
                        load_req <= load_req + 1;
                    end
                    if (load_pending) begin
                        weight_bank[load_channel][load_tap] <= wgt_rdata_i;
                        if (load_tap == taps-1) begin
                            load_tap <= 0; load_channel <= load_channel+1;
                        end else load_tap <= load_tap+1;
                        if (load_slot == total_weights-1) state <= RUN;
                    end
                end
                RUN: begin
                    operand_pending <= !issued_all;
                    if (!issued_all) begin
                        return_tap <= issue_tap;
                        if (issue_tap == taps-1) issued_all <= 1;
                        else begin
                            issue_tap <= issue_tap + 1;
                            if (c == int'(cfg_in_c_i)-1) begin
                                c <= 0;
                                if (s == 4) begin s <= 0; r <= r + 1; end
                                else s <= s + 1;
                            end else c <= c + 1;
                        end
                    end
                    if (operand_pending && return_tap == taps-1) begin
                        write_channel <= 0;
                        state <= WRITE;
                    end
                end
                WRITE: begin
                    if (write_channel == NUM_PE-1) begin
                        if (h == out_hw-1 && w == out_hw-1) state <= FINISH;
                        else begin
                            if (w == out_hw-1) begin w <= 0; h <= h+1; end
                            else w <= w+1;
                            r <= 0; s <= 0; c <= 0; issue_tap <= 0;
                            return_tap <= 0; operand_pending <= 0; issued_all <= 0;
                            state <= RUN;
                        end
                    end else write_channel <= write_channel + 1;
                end
                FINISH: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
