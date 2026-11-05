// MNIST CNN accelerator top level. Port list matches tb/tb_accelerator.sv in
// the course repo; do not rename ports.
//
//   csr  : activate / memory_location / length in, done / error out
//   xmem : external IMG, WGT, PARAM (read-only, owned by the testbench)
//   dbg  : read access to the internal ACT_A, ACT_B and RES memories
//
// Dataflow (one engine active at a time, chosen by the controller's layer):
//
//   conv1 : IMG   -> ACT_A   (a1, 1728 B)
//   pool1 : ACT_A -> ACT_B   (p1,  432 B)
//   conv2 : ACT_B -> ACT_A   (a2,  192 B, overwrites a1)
//   pool2 : ACT_A -> ACT_B   (p2,   48 B, overwrites p1)
//   fc    : ACT_B -> RES     (10 logits + argmax); controller then writes MAGIC
//
// Every read port seen by the engines and the controller has exactly one
// cycle of latency, whichever cnn_ext_mem mode is used: with an asynchronous
// external memory (REGISTERED_READ = 0) this module registers the read data;
// with a synchronous one it passes it through. XMEM_REGISTERED_READ must match
// the cnn_ext_mem REGISTERED_READ parameter.

module accelerator_top
    import accelerator_cnn_pkg::*;
    import acc_internal_pkg::*;
#(
    parameter bit XMEM_REGISTERED_READ = 1'b0
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    csr_accelerator_if.accelerator csr,
    cnn_mem_if.accelerator         xmem,
    acc_debug_if.accelerator       dbg,

    output logic        dbg_busy_o,
    output logic [31:0] dbg_cycles_o
);

    // ----- Controller -----
    layer_e                 layer;
    logic                   start, engine_done;
    logic [IMG_ADDR_W-1:0]  img_base;
    logic [4:0]             shift1, shift2;
    acc_t                   conv1_bias [C1_OC];
    acc_t                   conv2_bias [C2_OC];
    acc_t                   fc_bias    [FC_O];
    logic                   ctl_res_we;
    logic [RES_ADDR_W-1:0]  ctl_res_addr;
    logic [31:0]            ctl_res_wdata;
    logic [31:0]            par_rdata;

    acc_controller u_ctrl (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),
        .activate_i        (csr.activate),
        .memory_location_i (csr.memory_location),
        .length_i          (csr.length),
        .done_o            (csr.done),
        .error_o           (csr.error),
        .par_addr_o        (xmem.par_addr),
        .par_rdata_i       (par_rdata),
        .layer_o           (layer),
        .start_o           (start),
        .engine_done_i     (engine_done),
        .img_base_o        (img_base),
        .shift1_o          (shift1),
        .shift2_o          (shift2),
        .conv1_bias_o      (conv1_bias),
        .conv2_bias_o      (conv2_bias),
        .fc_bias_o         (fc_bias),
        .res_we_o          (ctl_res_we),
        .res_addr_o        (ctl_res_addr),
        .res_wdata_o       (ctl_res_wdata),
        .busy_o            (dbg_busy_o),
        .cycles_o          (dbg_cycles_o)
    );


    // ----- External Read Latency -> One Cycle -----
    act_t img_rdata;
    wgt_t wgt_rdata;

    if (XMEM_REGISTERED_READ) begin : g_xmem_sync
        assign img_rdata = xmem.img_rdata;
        assign wgt_rdata = xmem.wgt_rdata;
        assign par_rdata = xmem.par_rdata;
    end else begin : g_xmem_async
        always_ff @(posedge clk_i) begin
            img_rdata <= xmem.img_rdata;
            wgt_rdata <= xmem.wgt_rdata;
            par_rdata <= xmem.par_rdata;
        end
    end


    // ----- Internal Memories -----
    logic                    act_a_we, act_b_we, res_we;
    logic [ACT_A_ADDR_W-1:0] act_a_addr;
    logic [ACT_B_ADDR_W-1:0] act_b_addr;
    logic [RES_ADDR_W-1:0]   res_addr;
    act_t                    act_a_wdata, act_b_wdata, act_a_rdata, act_b_rdata;
    logic [31:0]             res_wdata, res_rdata;
    act_t                    act_a_dbg, act_b_dbg;
    logic [31:0]             res_dbg;

    acc_ram #(.WIDTH(8), .DEPTH(ACT_A_BYTES)) u_act_a (
        .clk_i     (clk_i),
        .a_we_i    (act_a_we),
        .a_addr_i  (act_a_addr),
        .a_wdata_i (act_a_wdata),
        .a_rdata_o (act_a_rdata),
        .b_addr_i  (dbg.addr[ACT_A_ADDR_W-1:0]),
        .b_rdata_o (act_a_dbg)
    );

    acc_ram #(.WIDTH(8), .DEPTH(ACT_B_BYTES)) u_act_b (
        .clk_i     (clk_i),
        .a_we_i    (act_b_we),
        .a_addr_i  (act_b_addr),
        .a_wdata_i (act_b_wdata),
        .a_rdata_o (act_b_rdata),
        .b_addr_i  (dbg.addr[ACT_B_ADDR_W-1:0]),
        .b_rdata_o (act_b_dbg)
    );

    acc_ram #(.WIDTH(32), .DEPTH(RES_WORDS)) u_res (
        .clk_i     (clk_i),
        .a_we_i    (res_we),
        .a_addr_i  (res_addr),
        .a_wdata_i (res_wdata),
        .a_rdata_o (res_rdata),
        .b_addr_i  (dbg.addr[RES_ADDR_W-1:0]),
        .b_rdata_o (res_dbg)
    );


    // ----- Engines -----
    logic                   conv_start, pool_start, fc_start;
    logic                   conv_done, pool_done, fc_done;
    logic [BYTE_ADDR_W-1:0] conv_src_addr, conv_dst_addr, pool_src_addr, pool_dst_addr;
    logic [BYTE_ADDR_W-1:0] fc_src_addr;
    logic [WGT_ADDR_W-1:0]  conv_wgt_addr, fc_wgt_addr;
    logic                   conv_dst_we, pool_dst_we, fc_res_we;
    act_t                   conv_dst_wdata, pool_dst_wdata, conv_src_rdata;
    logic [RES_ADDR_W-1:0]  fc_res_addr;
    logic [31:0]            fc_res_wdata;
    logic                   is_conv1;
    acc_t                   conv_bias [NUM_PE];

    assign is_conv1   = (layer == L_CONV1);
    always_comb begin
        for (int i = 0; i < NUM_PE; i++) begin
            conv_bias[i] = is_conv1 ? conv1_bias[i] : conv2_bias[i];
        end
    end
    assign conv_start = start && (layer == L_CONV1 || layer == L_CONV2);
    assign pool_start = start && (layer == L_POOL1 || layer == L_POOL2);
    assign fc_start   = start && (layer == L_FC);

    acc_conv u_conv (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .start_i        (conv_start),
        .done_o         (conv_done),
        .cfg_in_hw_i    (is_conv1 ? 5'(IMG_H) : 5'(P1_H)),
        .cfg_in_c_i     (is_conv1 ? 2'(IMG_C) : 2'(C1_OC)),
        .cfg_src_base_i (is_conv1 ? BYTE_ADDR_W'(img_base) : '0),
        .cfg_wgt_base_i (is_conv1 ? WGT_ADDR_W'(WGT_CONV1_BASE)
                                  : WGT_ADDR_W'(WGT_CONV2_BASE)),
        .cfg_shift_i    (is_conv1 ? shift1 : shift2),
        .cfg_bias_i     (conv_bias),
        .src_addr_o     (conv_src_addr),
        .src_rdata_i    (conv_src_rdata),
        .wgt_addr_o     (conv_wgt_addr),
        .wgt_rdata_i    (wgt_rdata),
        .dst_we_o       (conv_dst_we),
        .dst_addr_o     (conv_dst_addr),
        .dst_wdata_o    (conv_dst_wdata)
    );

    acc_pool u_pool (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .start_i     (pool_start),
        .done_o      (pool_done),
        .cfg_in_hw_i (layer == L_POOL1 ? 5'(A1_H) : 5'(A2_H)),
        .src_addr_o  (pool_src_addr),
        .src_rdata_i (act_a_rdata),
        .dst_we_o    (pool_dst_we),
        .dst_addr_o  (pool_dst_addr),
        .dst_wdata_o (pool_dst_wdata)
    );

    acc_fc u_fc (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .start_i     (fc_start),
        .done_o      (fc_done),
        .cfg_bias_i  (fc_bias),
        .src_addr_o  (fc_src_addr),
        .src_rdata_i (act_b_rdata),
        .wgt_addr_o  (fc_wgt_addr),
        .wgt_rdata_i (wgt_rdata),
        .res_we_o    (fc_res_we),
        .res_addr_o  (fc_res_addr),
        .res_wdata_o (fc_res_wdata)
    );


    // ----- Memory Port Routing -----
    always_comb begin
        // External memories
        xmem.img_addr = is_conv1 ? IMG_ADDR_W'(conv_src_addr) : '0;
        xmem.wgt_addr = (layer == L_FC) ? fc_wgt_addr : conv_wgt_addr;

        // conv reads IMG for conv1, ACT_B for conv2
        conv_src_rdata = is_conv1 ? img_rdata : act_b_rdata;

        // ACT_A: written by conv, read by pool
        act_a_we    = 1'b0;
        act_a_addr  = ACT_A_ADDR_W'(pool_src_addr);
        act_a_wdata = conv_dst_wdata;

        // ACT_B: written by pool, read by conv2 and fc
        act_b_we    = 1'b0;
        act_b_addr  = ACT_B_ADDR_W'(pool_dst_addr);
        act_b_wdata = pool_dst_wdata;

        // RES: written by fc during L_FC, by the controller otherwise
        res_we    = ctl_res_we;
        res_addr  = ctl_res_addr;
        res_wdata = ctl_res_wdata;

        unique case (layer)
            L_CONV1: begin
                act_a_we   = conv_dst_we;
                act_a_addr = ACT_A_ADDR_W'(conv_dst_addr);
            end
            L_POOL1, L_POOL2: begin
                act_b_we   = pool_dst_we;
            end
            L_CONV2: begin
                act_a_we   = conv_dst_we;
                act_a_addr = ACT_A_ADDR_W'(conv_dst_addr);
                act_b_addr = ACT_B_ADDR_W'(conv_src_addr);
            end
            L_FC: begin
                act_b_addr = ACT_B_ADDR_W'(fc_src_addr);
                res_we     = fc_res_we;
                res_addr   = fc_res_addr;
                res_wdata  = fc_res_wdata;
            end
            default: ;
        endcase
    end

    always_comb begin
        unique case (layer)
            L_CONV1, L_CONV2: engine_done = conv_done;
            L_POOL1, L_POOL2: engine_done = pool_done;
            L_FC:             engine_done = fc_done;
            default:          engine_done = 1'b0;
        endcase
    end


    // ----- Debug Read Port (one cycle latency, like the RAM ports) -----
    mem_sel_e dbg_sel_q;

    always_ff @(posedge clk_i) begin
        dbg_sel_q <= dbg.sel;
    end

    always_comb begin
        unique case (dbg_sel_q)
            MEM_ACT_A: dbg.rdata = {24'd0, act_a_dbg};
            MEM_ACT_B: dbg.rdata = {24'd0, act_b_dbg};
            MEM_RES:   dbg.rdata = res_dbg;
            default:   dbg.rdata = '0;
        endcase
    end

    // verilator lint_off UNUSEDSIGNAL
    logic unused;
    assign unused = ^{res_rdata, dbg.addr};
    // verilator lint_on UNUSEDSIGNAL

endmodule
