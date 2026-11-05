// ===========================================================================
// tb_team.sv -- our own accelerator testbench.
//
// Mirrors the checks in the course tb/tb_accelerator.sv, which cannot run
// yet (it needs acc_check.svh, cnn_golden_model and the real acc_debug_if),
// and adds a few of our own. Golden data comes straight from the course
// vector directories.
//
//   +vectors=<dir>   course tb/vectors directory (required)
//   +bringup=N       check only layer N of every vector: 1=a1 (ACT_A),
//                    2=p1 (ACT_B), 3=a2 (ACT_A), 4=p2 (ACT_B). Use while
//                    later layers are still stubs. Default: full checks.
//   -GSYNC=1         run cnn_ext_mem with REGISTERED_READ=1
// ===========================================================================
module tb_team #(
    parameter bit SYNC = 1'b0
);

    import accelerator_cnn_pkg::*;

    logic clk = 0;
    logic rst_n;
    always #5 clk = ~clk;

    csr_accelerator_if csr_if  ();
    cnn_mem_if         xmem_if ();
    acc_debug_if       acc_dbg ();

    cnn_ext_mem #(.REGISTERED_READ(SYNC)) xmem (
        .clk_i (clk),
        .bus   (xmem_if)
    );

    logic        dut_busy;
    logic [31:0] dut_cycles;

    accelerator_top #(.XMEM_REGISTERED_READ(SYNC)) dut (
        .clk_i        (clk),
        .rst_ni       (rst_n),
        .csr          (csr_if),
        .xmem         (xmem_if),
        .dbg          (acc_dbg),
        .dbg_busy_o   (dut_busy),
        .dbg_cycles_o (dut_cycles)
    );

    string vec_root;
    int    bringup;
    int    total_errors = 0;
    int    total_checks = 0;

    // ----- golden data for the currently loaded vector ----------------------
    logic [7:0]  gold_a1 [A1_ELEMS];
    logic [7:0]  gold_p1 [P1_ELEMS];
    logic [7:0]  gold_a2 [A2_ELEMS];
    logic [7:0]  gold_p2 [P2_ELEMS];
    logic [31:0] gold_res [RES_WORDS];

    // Check each layer's writes before the following layer reuses its buffer.
    // Also verify address order/count, catching missing or duplicate outputs.
    int stage_errors [4];
    int stage_writes [4];
    always @(posedge clk) begin : monitor_datapath
        int n, addr, count;
        logic [7:0] got, exp;
        if (rst_n) begin
            n = -1; addr = 0; got = 0; exp = 0; count = 0;
            if (dut.conv_dst_we) begin
                n = dut.layer == acc_internal_pkg::L_CONV1 ? 0 : 2;
                addr = int'(dut.conv_dst_addr);
                got = dut.conv_dst_wdata;
                count = n == 0 ? A1_ELEMS : A2_ELEMS;
                if (addr < count) exp = n == 0 ? gold_a1[addr] : gold_a2[addr];
            end else if (dut.pool_dst_we) begin
                n = dut.layer == acc_internal_pkg::L_POOL1 ? 1 : 3;
                addr = int'(dut.pool_dst_addr);
                got = dut.pool_dst_wdata;
                count = n == 1 ? P1_ELEMS : P2_ELEMS;
                if (addr < count) exp = n == 1 ? gold_p1[addr] : gold_p2[addr];
            end
            if (n >= 0) begin
                if (addr >= count || addr != stage_writes[n] || got !== exp) begin
                    if (stage_errors[n] < 4)
                        $display("      layer %0d write mismatch addr=%0d got=%0d expected=%0d",
                                 n+1, addr, got, exp);
                    stage_errors[n]++;
                end
                stage_writes[n]++;
            end
        end
    end

    task automatic load_vector(input string name);
        string d;
        begin
            for (int i=0; i<4; i++) begin stage_errors[i]=0; stage_writes[i]=0; end
            d = {vec_root, "/", name};
            xmem.load(d);
            $readmemh({d, "/golden_a1.hex"}, gold_a1);
            $readmemh({d, "/golden_p1.hex"}, gold_p1);
            $readmemh({d, "/golden_a2.hex"}, gold_a2);
            $readmemh({d, "/golden_p2.hex"}, gold_p2);
            $readmemh({d, "/expected.hex"},  gold_res);
        end
    endtask

    function automatic void report(input string what, input int errs);
        total_checks++;
        total_errors += errs;
        if (errs == 0) $display("  ok   %s", what);
        else           $display("  FAIL %s (%0d errors)", what, errs);
    endfunction

    // ----- debug-port reads (one cycle latency) -----------------------------
    task automatic dbg_read(input mem_sel_e sel, input int addr,
                            output logic [31:0] data);
        begin
            @(negedge clk);
            acc_dbg.sel  = sel;
            acc_dbg.addr = 11'(addr);
            @(negedge clk);
            data = acc_dbg.rdata;
        end
    endtask

    // Compare n entries of an internal memory against golden data.
    task automatic cmp_mem(input mem_sel_e sel, input int n, input int which,
                           output int errs);
        logic [31:0] got, exp;
        begin
            errs = 0;
            for (int i = 0; i < n; i++) begin
                dbg_read(sel, i, got);
                case (which)
                    1: exp = {24'd0, gold_a1[i]};
                    2: exp = {24'd0, gold_p1[i]};
                    3: exp = {24'd0, gold_a2[i]};
                    4: exp = {24'd0, gold_p2[i]};
                    default: exp = gold_res[i];
                endcase
                if (got !== exp) begin
                    if (errs < 4)
                        $display("      mismatch idx %0d: got %08h expected %08h",
                                 i, got, exp);
                    errs++;
                end
            end
        end
    endtask

    task automatic check_layer(input int n, output int errs);
        case (n)
            1: errs = stage_errors[0] + (stage_writes[0] == A1_ELEMS ? 0 : 1);
            2: errs = stage_errors[1] + (stage_writes[1] == P1_ELEMS ? 0 : 1);
            3: cmp_mem(MEM_ACT_A, A2_ELEMS, 3, errs);
            default: cmp_mem(MEM_ACT_B, P2_ELEMS, 4, errs);
        endcase
    endtask

    task automatic check_res(output int errs);
        cmp_mem(MEM_RES, RES_MAGIC + 1, 0, errs);
    endtask

    // ----- CSR handshake ----------------------------------------------------
    task automatic do_reset();
        begin
            csr_if.activate        = 1'b0;
            csr_if.memory_location = '0;
            csr_if.length          = '0;
            acc_dbg.sel            = MEM_RES;
            acc_dbg.addr           = '0;
            rst_n = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    // Raise activate, wait for done, check done is a held level, drop
    // activate, check done clears. Returns handshake errors in herrs.
    task automatic run_job(input logic [31:0] loc, input logic [31:0] len,
                           output int cycles, output logic err, output int herrs);
        int guard;
        begin
            herrs  = 0;
            cycles = 0;
            guard  = 0;
            @(negedge clk);
            for (int i=0; i<4; i++) begin stage_errors[i]=0; stage_writes[i]=0; end
            csr_if.memory_location = loc;
            csr_if.length          = len;
            csr_if.activate        = 1'b1;
            while (!csr_if.done && guard < 2_000_000) begin
                @(posedge clk); cycles++; guard++;
            end
            if (!csr_if.done) begin
                $display("      job never asserted done");
                herrs++;
            end
            err = csr_if.error;
            if (!err && csr_if.done) begin
                for (int i=0; i<4; i++) herrs += stage_errors[i];
                if (stage_writes[0] != A1_ELEMS || stage_writes[1] != P1_ELEMS ||
                    stage_writes[2] != A2_ELEMS || stage_writes[3] != P2_ELEMS) begin
                    $display("      incomplete layer write counts: %0d %0d %0d %0d",
                             stage_writes[0],stage_writes[1],stage_writes[2],stage_writes[3]);
                    herrs++;
                end
            end

            // done is a level that holds, and the job does not restart, while
            // activate stays high
            repeat (20) @(posedge clk);
            if (!csr_if.done) begin
                $display("      done did not hold while activate was high");
                herrs++;
            end
            if (dut_busy) begin
                $display("      accelerator restarted while activate stayed high");
                herrs++;
            end

            @(negedge clk);
            csr_if.activate = 1'b0;
            guard = 0;
            while (csr_if.done && guard < 1000) begin
                @(posedge clk); guard++;
            end
            if (csr_if.done) begin
                $display("      done did not clear after activate dropped");
                herrs++;
            end
        end
    endtask

    // ----- one vector, end to end -------------------------------------------
    task automatic check_vector(input string name, input logic [31:0] offset);
        int cyc, herrs, e;
        logic err;
        begin
            load_vector(name);
            run_job(offset, IMG_PIXELS, cyc, err, herrs);
            if (err) begin
                $display("      raised error unexpectedly");
                herrs++;
            end
            if (bringup != 0) check_layer(bringup, e);
            else              check_res(e);
            report($sformatf("%-10s %s  %6d cycles", name,
                             bringup != 0 ? $sformatf("layer %0d", bringup)
                                          : "result ",
                             cyc), herrs + e);
        end
    endtask

    // -----------------------------------------------------------------------
    initial begin
        int cyc, herrs, e, e2;
        logic err;
        logic [31:0] word;

        if (!$value$plusargs("vectors=%s", vec_root)) begin
            $display("tb_team: pass +vectors=<course tb/vectors dir>");
            $fatal(1);
        end
        if (!$value$plusargs("bringup=%d", bringup)) bringup = 0;

        $display("=== tb_team  (cnn_ext_mem REGISTERED_READ=%0d, %s) ===", SYNC,
                 bringup != 0 ? $sformatf("bring-up: layer %0d", bringup)
                              : "full checks");
        do_reset();

        // ---- 1. every vector ---------------------------------------------
        check_vector("v0_box",    32'h000);
        check_vector("v1_ramp",   32'h000);
        check_vector("v2_random", 32'h000);
        check_vector("v3_zeros",  32'h000);
        check_vector("v4_ones",   32'h000);
        check_vector("v5_offset", 32'h400);   // second image slot

        // ---- 2. conv2 / pool2 left in ACT_A / ACT_B after a full job -------
        if (bringup == 0) begin
            load_vector("v2_random");
            run_job(32'h000, IMG_PIXELS, cyc, err, herrs);
            check_layer(3, e);
            check_layer(4, e2);
            report("layer-by-layer: conv2 and pool2 match golden", herrs + e + e2);
        end

        // ---- 3. repeated job gives the same answer -------------------------
        load_vector("v0_box");
        run_job(32'h000, IMG_PIXELS, cyc, err, herrs);
        run_job(32'h000, IMG_PIXELS, cyc, err, e2);
        if (bringup != 0) check_layer(bringup, e);
        else              check_res(e);
        report("repeated job", herrs + e2 + e);

        // ---- 4. bad length: error + done, MAGIC cleared --------------------
        run_job(32'h000, 32'd123, cyc, err, herrs);
        dbg_read(MEM_RES, RES_MAGIC, word);
        report("bad length raises error and completes",
               herrs + (err ? 0 : 1) + (word == 32'd0 ? 0 : 1));

        // ---- 5. bad offset (our assumption: image must fit in IMG) ---------
        run_job(32'h600, IMG_PIXELS, cyc, err, herrs);
        report("offset past end of IMG raises error", herrs + (err ? 0 : 1));

        // ---- 6. error is cleared by the next good job ----------------------
        check_vector("v1_ramp", 32'h000);
        if (csr_if.error) report("error clears on next job", 1);

        // ---- 7. reset mid-job ----------------------------------------------
        load_vector("v0_box");
        @(negedge clk);
        csr_if.memory_location = 32'h000;
        csr_if.length          = IMG_PIXELS;
        csr_if.activate        = 1'b1;
        repeat (500) @(posedge clk);
        do_reset();
        e = (csr_if.done || csr_if.error || dut_busy) ? 1 : 0;
        run_job(32'h000, IMG_PIXELS, cyc, err, herrs);
        if (bringup != 0) check_layer(bringup, e2);
        else              check_res(e2);
        report("recovers from mid-job reset", e + herrs + e2);

        // Reset with a pooling window in flight, then verify a fresh job.
        load_vector("v2_random");
        @(negedge clk);
        csr_if.memory_location = 0;
        csr_if.length = IMG_PIXELS;
        csr_if.activate = 1;
        begin
            int guard;
            guard = 0;
            while (!dut.pool_dst_we && guard < 100_000) begin
                @(negedge clk); guard++;
            end
            if (!dut.pool_dst_we) $fatal(1,"Pooling did not start before reset test");
        end
        do_reset();
        e = (csr_if.done || csr_if.error || dut_busy || dut.conv_dst_we || dut.pool_dst_we) ? 1 : 0;
        run_job(0, IMG_PIXELS, cyc, err, herrs);
        check_layer(4, e2);
        report("recovers from reset during pooling", e + herrs + e2 + (err ? 1 : 0));

        $display("");
        if (total_errors == 0) $display("TB_TEAM PASS (%0d checks)", total_checks);
        else $fatal(1, "TB_TEAM FAIL (%0d errors across %0d checks)",
                    total_errors, total_checks);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TB_TEAM TIMEOUT");
        $fatal(1);
    end

endmodule
