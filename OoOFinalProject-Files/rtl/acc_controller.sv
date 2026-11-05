// Job controller: CSR handshake, configuration checks, PARAM preload, layer
// sequencing, and completion.
//
//   IDLE --activate--> CHECK --bad length/offset--------------------+
//                        |                                          |
//                        v                                          |
//                  PARAM_ADDR <-> PARAM_DATA  (words 0..19)         |
//                        |                                          |
//                        v                                          |
//                     PCHECK --bad magic/version-------------------+
//                        |                                          |
//                        v                                          |
//          +------> START --> WAIT --engine done, not FC--+         |
//          +----------------------------------------------+         |
//                                  | FC done                        |
//                                  v                                v
//                               MAGIC -----------------------> DONE (done=1)
//                                                                   |
//                                                     activate == 0 |
//                                                                   v
//                                                                 IDLE
//
// Completion is a level: done stays high in DONE until activate drops, so a
// still-high activate can never restart the job. error is cleared when a job
// starts and held until the next one. The controller owns the PARAM port and
// hands shifts and biases to the engines, so engines never read PARAM.

module acc_controller
    import accelerator_cnn_pkg::*;
    import acc_internal_pkg::*;
(
    input  logic                    clk_i,
    input  logic                    rst_ni,

    // CSR job interface
    input  logic                    activate_i,
    input  logic [31:0]             memory_location_i,
    input  logic [31:0]             length_i,
    output logic                    done_o,
    output logic                    error_o,

    // PARAM read port - data valid the cycle after the address
    output logic [PARAM_ADDR_W-1:0] par_addr_o,
    input  logic [31:0]             par_rdata_i,

    // Layer sequencing - start is a one-cycle pulse, engine_done a pulse
    output layer_e                  layer_o,
    output logic                    start_o,
    input  logic                    engine_done_i,

    // Configuration for the engines, stable for the whole job
    output logic [IMG_ADDR_W-1:0]   img_base_o,
    output logic [4:0]              shift1_o,
    output logic [4:0]              shift2_o,
    output acc_t                    conv1_bias_o [C1_OC],
    output acc_t                    conv2_bias_o [C2_OC],
    output acc_t                    fc_bias_o    [FC_O],

    // RES write port, used only outside L_FC (clear and write MAGIC)
    output logic                    res_we_o,
    output logic [RES_ADDR_W-1:0]   res_addr_o,
    output logic [31:0]             res_wdata_o,

    // Debug
    output logic                    busy_o,
    output logic [31:0]             cycles_o
);

    typedef enum logic [3:0] {
        S_IDLE,
        S_CHECK,
        S_PARAM_ADDR,
        S_PARAM_DATA,
        S_PCHECK,
        S_START,
        S_WAIT,
        S_MAGIC,
        S_DONE
    } state_e;

    // Last PARAM word the controller needs: fc bias[9].
    localparam int unsigned PAR_LAST = PAR_FC_B + FC_O - 1;   // 19

    state_e                  state_q, state_d;
    layer_e                  layer_q;
    logic                    error_q;
    logic [31:0]             loc_q, len_q;
    logic [PARAM_ADDR_W-1:0] par_idx_q;
    logic [31:0]             par_q [PAR_LAST + 1];
    logic [31:0]             cycles_q;

    // ----- Configuration checks -----
    // ASSUMPTION (confirm on Campuswire): an offset is valid when the whole
    // 784-byte image fits in IMG, not only the two slot bases 0x000/0x400.
    logic cfg_ok, par_ok;
    assign cfg_ok = (len_q == IMG_PIXELS) &&
                    (loc_q <= IMG_MEM_BYTES - IMG_PIXELS);
    // ASSUMPTION (confirm on Campuswire): a bad MAGIC or version is an error.
    assign par_ok = (par_q[PAR_MAGIC] == MAGIC) &&
                    (par_q[PAR_VERSION] == VERSION);


    // ----- Next State -----
    always_comb begin
        state_d = state_q;
        unique case (state_q)
            S_IDLE:       if (activate_i)                  state_d = S_CHECK;
            S_CHECK:      state_d = cfg_ok ? S_PARAM_ADDR : S_DONE;
            S_PARAM_ADDR: state_d = S_PARAM_DATA;
            S_PARAM_DATA: state_d = (par_idx_q == PARAM_ADDR_W'(PAR_LAST)) ? S_PCHECK
                                                             : S_PARAM_ADDR;
            S_PCHECK:     state_d = par_ok ? S_START : S_DONE;
            S_START:      state_d = S_WAIT;
            S_WAIT:       if (engine_done_i)
                              state_d = (layer_q == L_FC) ? S_MAGIC : S_START;
            S_MAGIC:      state_d = S_DONE;
            S_DONE:       if (!activate_i)                 state_d = S_IDLE;
            default:      state_d = S_IDLE;
        endcase
    end


    // ----- State, Configuration and Counters -----
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q   <= S_IDLE;
            layer_q   <= L_NONE;
            error_q   <= 1'b0;
            loc_q     <= '0;
            len_q     <= '0;
            par_idx_q <= '0;
            cycles_q  <= '0;
            for (int i = 0; i <= PAR_LAST; i++) par_q[i] <= '0;
        end else begin
            state_q <= state_d;

            unique case (state_q)
                S_IDLE: if (activate_i) begin
                    // Capture the job; CSR writes during the job are ignored.
                    loc_q     <= memory_location_i;
                    len_q     <= length_i;
                    error_q   <= 1'b0;
                    cycles_q  <= '0;
                    par_idx_q <= '0;
                    layer_q   <= L_NONE;
                end
                S_CHECK:  if (!cfg_ok) error_q <= 1'b1;
                S_PARAM_DATA: begin
                    par_q[par_idx_q] <= par_rdata_i;
                    par_idx_q        <= par_idx_q + 1'b1;
                end
                S_PCHECK: begin
                    if (!par_ok) error_q <= 1'b1;
                    layer_q <= L_CONV1;
                end
                // Release the memory ports after FC so the MAGIC write in
                // S_MAGIC reaches RES through the controller's port.
                S_WAIT: if (engine_done_i) begin
                    layer_q <= (layer_q == L_FC) ? L_NONE
                                                 : layer_e'(layer_q + 1'b1);
                end
                default: ;
            endcase

            if (busy_o) cycles_q <= cycles_q + 1'b1;
        end
    end


    // ----- Outputs -----
    assign done_o     = (state_q == S_DONE);
    assign error_o    = error_q;
    assign busy_o     = (state_q != S_IDLE) && (state_q != S_DONE);
    assign cycles_o   = cycles_q;
    assign par_addr_o = par_idx_q;
    assign layer_o    = layer_q;
    assign start_o    = (state_q == S_START);

    assign img_base_o = loc_q[IMG_ADDR_W-1:0];
    assign shift1_o   = par_q[PAR_SHIFT1][4:0];
    assign shift2_o   = par_q[PAR_SHIFT2][4:0];
    for (genvar i = 0; i < C1_OC; i++) begin : g_c1b
        assign conv1_bias_o[i] = par_q[PAR_CONV1_B + i];
    end
    for (genvar i = 0; i < C2_OC; i++) begin : g_c2b
        assign conv2_bias_o[i] = par_q[PAR_CONV2_B + i];
    end
    for (genvar i = 0; i < FC_O; i++) begin : g_fcb
        assign fc_bias_o[i] = par_q[PAR_FC_B + i];
    end

    // RES: clear MAGIC when a job is accepted, write it as the very last
    // step of a successful job. Software polling RES_MAGIC never sees a
    // stale value from the previous job.
    assign res_we_o    = (state_q == S_CHECK) || (state_q == S_MAGIC);
    assign res_addr_o  = RES_ADDR_W'(RES_MAGIC);
    assign res_wdata_o = (state_q == S_MAGIC) ? MAGIC : 32'd0;

endmodule
