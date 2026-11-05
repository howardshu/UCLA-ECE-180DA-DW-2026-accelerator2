// Unsigned 2x2 stride-2 max pooling, ACT_A -> ACT_B, HWC layout.
// Four pipelined reads and one write per output. Config is stable until done.
module acc_pool
    import accelerator_cnn_pkg::*;
    import acc_internal_pkg::*;
(
    input  logic                   clk_i,
    input  logic                   rst_ni,

    input  logic                   start_i,
    output logic                   done_o,

    input  logic [4:0]             cfg_in_hw_i,      // 24 or 8

    // Input activations (ACT_A)
    output logic [BYTE_ADDR_W-1:0] src_addr_o,
    input  act_t                   src_rdata_i,

    // Output activations (ACT_B)
    output logic                   dst_we_o,
    output logic [BYTE_ADDR_W-1:0] dst_addr_o,
    output act_t                   dst_wdata_o
);

    typedef enum logic [1:0] {IDLE, READ, WRITE, FINISH} state_t;
    state_t state;
    int unsigned h, w, channel, issue_sample, out_hw;
    logic pending;
    logic [1:0] return_sample;
    act_t maximum;
    assign out_hw = int'(cfg_in_hw_i) / 2;
    // Sample order: top left, top right, bottom left, bottom right.
    assign src_addr_o = BYTE_ADDR_W'(
        ((2*h + ((issue_sample < 4 ? issue_sample : 0)/2))*int'(cfg_in_hw_i) +
          2*w + ((issue_sample < 4 ? issue_sample : 0)%2))*C1_OC + channel);
    assign dst_addr_o = BYTE_ADDR_W'((h*out_hw+w)*C1_OC + channel);
    assign dst_we_o = rst_ni && state == WRITE;
    assign dst_wdata_o = maximum;
    assign done_o = state == FINISH;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            h <= 0; w <= 0; channel <= 0; issue_sample <= 0;
            pending <= 0; return_sample <= 0; maximum <= 0;
        end else begin
            case (state)
                IDLE: if (start_i) begin
                    h <= 0; w <= 0; channel <= 0; issue_sample <= 0;
                    pending <= 0; maximum <= 0;
                    state <= READ;
                end
                READ: begin
                    pending <= issue_sample < 4;
                    if (issue_sample < 4) begin
                        return_sample <= 2'(issue_sample);
                        issue_sample <= issue_sample + 1;
                    end
                    if (pending) begin
                        if (src_rdata_i > maximum) maximum <= src_rdata_i;
                        if (return_sample == 3) state <= WRITE;
                    end
                end
                WRITE: begin
                    if (h == out_hw-1 && w == out_hw-1 && channel == C1_OC-1)
                        state <= FINISH;
                    else begin
                        if (channel == C1_OC-1) begin
                            channel <= 0;
                            if (w == out_hw-1) begin w <= 0; h <= h+1; end
                            else w <= w+1;
                        end else channel <= channel+1;
                        maximum <= 0; pending <= 0; issue_sample <= 0;
                        state <= READ;
                    end
                end
                FINISH: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
