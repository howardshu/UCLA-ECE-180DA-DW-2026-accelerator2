`timescale 1ns/1ps
module tb_pe;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, clear = 0, valid = 0, first_mac = 0;
    logic [7:0] act = 0;
    logic signed [7:0] wgt = 0;
    logic signed [31:0] bias = 0, sum;
    logic [4:0] shift = 0;
    logic [7:0] quant;
    logic signed [15:0] small_sum;
    logic [3:0] small_quant;
    logic signed [31:0] expected = 0;
    logic signed [15:0] small_expected = 0;
    int checks = 0;
    string dir;
    logic [7:0] img [2048], weights [1024], p1 [432], p2 [48];
    logic [7:0] a1 [1728], a2 [192];
    logic [31:0] params [32], results [16];

    pe_top dut (.clk_i(clk), .rst_ni(rst_n), .clear_i(clear),
        .valid_i(valid), .first_mac_i(first_mac), .act_i(act), .wgt_i(wgt),
        .bias_i(bias), .shift_i(shift), .sum_o(sum), .requant_o(quant));
    pe_top #(.DATA_W(4), .ACC_W(16)) small_dut (
        .clk_i(clk), .rst_ni(rst_n), .clear_i(clear), .valid_i(valid),
        .first_mac_i(first_mac), .act_i(act[3:0]), .wgt_i(wgt[3:0]),
        .bias_i(bias[15:0]), .shift_i(shift[3:0]),
        .sum_o(small_sum), .requant_o(small_quant));

    task automatic check_outputs;
        int signed shifted, sq;
        shifted = expected >>> shift;
        sq = int'(small_expected) >>> shift[3:0];
        if (sum !== expected ||
            int'(quant) != (shifted < 0 ? 0 : shifted > 255 ? 255 : shifted))
            $fatal(1, "PE mismatch check=%0d sum=%0d expected=%0d quant=%0d", checks, sum, expected, quant);
        if (small_sum !== small_expected ||
            int'(small_quant) != (sq < 0 ? 0 : sq > 15 ? 15 : sq))
            $fatal(1, "Parameterized PE mismatch check=%0d", checks);
        checks++;
    endtask

    task automatic step(input bit v, f, cl, input int a, w, b, s);
        @(negedge clk);
        valid = v; first_mac = f; clear = cl;
        act = 8'(a); wgt = 8'(w); bias = b; shift = 5'(s);
        if (!rst_n || cl) begin
            expected = 0; small_expected = 0;
        end else if (v) begin
            expected = (f ? b : expected) + a * w;
            small_expected = 16'((f ? int'($signed(bias[15:0])) : int'(small_expected)) +
                                int'(act[3:0]) * int'($signed(wgt[3:0])));
        end
        @(posedge clk); #1;
        check_outputs();
    endtask

    // Isolate each layer using course golden inputs; check every MAC against
    // integer arithmetic and each completed output against the supplied files.
    task automatic conv_layer(input bit second, input int offset);
        int hw, channels, oh, base, bp, sh, xi, wi, a;
        hw = second ? 12 : 28; channels = second ? 3 : 1;
        oh = hw - 4; base = second ? 'h80 : 0; bp = second ? 7 : 4;
        sh = int'(params[second ? 3 : 2]);
        for (int h=0; h<oh; h++)
            for (int x=0; x<oh; x++)
                for (int o=0; o<3; o++) begin
                    for (int r=0; r<5; r++)
                        for (int s=0; s<5; s++)
                            for (int c=0; c<channels; c++) begin
                                xi = ((h+r)*hw+x+s)*channels+c;
                                wi = base+((o*5+r)*5+s)*channels+c;
                                a = second ? int'(p1[xi]) : int'(img[offset+xi]);
                                step(1, r==0 && s==0 && c==0, 0, a,
                                     int'($signed(weights[wi])), int'(params[bp+o]), sh);
                            end
                    if (quant !== (second ? a2[(h*oh+x)*3+o] : a1[(h*oh+x)*3+o]))
                        $fatal(1, "Conv%0d golden mismatch h=%0d w=%0d o=%0d", second+1,h,x,o);
                end
    endtask

    initial begin
        int offset;
        if (!$value$plusargs("vector=%s", dir)) $fatal(1, "Missing +vector=directory");
        if (!$value$plusargs("offset=%d", offset)) offset=0;
        #1; expected=0; small_expected=0;
        @(negedge clk); rst_n=1;
        step(1,1,0,255,-128,17,0);
        step(0,1,0,255,127,999,31); // stall must ignore first/bias
        step(1,0,0,128,127,999,7);
        step(1,1,0,255,127,-1,0); // back-to-back output, no clear bubble
        step(1,1,1,255,127,100,0); // clear wins over valid/first
        step(1,1,0,0,0,255,0);
        step(1,1,0,0,0,256,0);
        step(1,1,0,0,0,-1,31);
        step(1,1,0,1,1,32'sh7fffffff,0); // defined 32-bit wrap
        step(1,1,0,1,-1,32'sh80000000,0);
        // Reset while a dot product is in progress, between clock edges.
        @(negedge clk); #1; rst_n=0; valid=0; expected=0; small_expected=0;
        #1; check_outputs();
        @(negedge clk); rst_n=1;
        for (int i=0; i<1000; i++)
            step($urandom_range(0,1)!=0, $urandom_range(0,3)==0,
                 $urandom_range(0,31)==0, int'($urandom_range(0,255)),
                 int'($urandom_range(0,255))-128, int'($urandom()),
                 int'($urandom_range(0,31)));
        $readmemh({dir,"/img_mem.hex"},img);
        $readmemh({dir,"/wgt_mem.hex"},weights);
        $readmemh({dir,"/param_mem.hex"},params);
        $readmemh({dir,"/golden_p1.hex"},p1);
        $readmemh({dir,"/golden_p2.hex"},p2);
        $readmemh({dir,"/golden_a1.hex"},a1);
        $readmemh({dir,"/golden_a2.hex"},a2);
        $readmemh({dir,"/expected.hex"},results);
        conv_layer(0,offset);
        conv_layer(1,0);
        for (int o=0; o<10; o++) begin
            for (int i=0; i<48; i++)
                step(1,i==0,0,int'(p2[i]),int'($signed(weights['h180+o*48+i])),
                     int'(params[10+o]),0);
            if (sum !== results[o]) $fatal(1,"FC golden mismatch o=%0d",o);
        end
        $display("PASS %s: %0d cycle checks, conv1/conv2 outputs and 10 FC logits",dir,checks);
        $finish;
    end
endmodule
