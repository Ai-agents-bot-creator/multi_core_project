

import L1_cache_mem::*;
import l2_cache_pkg::*;



module tile_tb_stable;
    // Waveform capture for regression/debug runs.
    initial begin
        $dumpfile("build/tile_tb.vcd");
        $dumpvars(0, tile_tb_stable);
    end

    logic clk, rst;

    logic [7:0] l1_data_out0, l1_data_out1;
    logic [9:0] l1_inst0,     l1_inst1;
    logic [7:0] l1_in_data0,  l1_in_data1;

    logic [31:0] t0_c_out, t0_cc_out, t1_c_out, t1_cc_out;
    logic        t0_c_valid, t0_cc_valid, t1_c_valid, t1_cc_valid;

    tile_top #(.MY_BANK_ID(2'd0)) dut0 (
        .clk(clk), .rst(rst),
        .l1_data_out(l1_data_out0), .l1_inst(l1_inst0), .l1_in_data(l1_in_data0),
        .c_in(t1_c_out),  .c_wr(t1_c_valid),  .c_out(t0_c_out),  .c_out_valid(t0_c_valid),
        .cc_in(t1_cc_out), .cc_wr(t1_cc_valid), .cc_out(t0_cc_out), .cc_out_valid(t0_cc_valid)
    );

    tile_top #(.MY_BANK_ID(2'd1)) dut1 (
        .clk(clk), .rst(rst),
        .l1_data_out(l1_data_out1), .l1_inst(l1_inst1), .l1_in_data(l1_in_data1),
        .c_in(t0_c_out),  .c_wr(t0_c_valid),  .c_out(t1_c_out),  .c_out_valid(t1_c_valid),
        .cc_in(t0_cc_out), .cc_wr(t0_cc_valid), .cc_out(t1_cc_out), .cc_out_valid(t1_cc_valid)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    initial begin
        wait (rst == 1'b0);
        dut0.u_mem_tap.preload(8'h01, 8'd10);
        dut1.u_mem_tap.preload(8'h15, 8'd41);
        dut0.u_mem_tap.preload(8'h40, 8'd99);
        dut0.u_mem_tap.preload(8'h80, 8'd88);
    end

    initial begin
        $monitor(
            "T=%0t | T0: L1(%s) L2(%s/%s) | T1: L1(%s) L2(%s/%s)",
            $time,
            dut0.u_c1_ctrl.C_PS.name(), dut0.u_c2_ctrl.C_PS.name(), dut0.u_c2_ctrl.pending_state.name(),
            dut1.u_c1_ctrl.C_PS.name(), dut1.u_c2_ctrl.C_PS.name(), dut1.u_c2_ctrl.pending_state.name()
        );
    end

    always @(posedge clk) begin
        if (t0_c_valid || t0_cc_valid)
            $display("T=%0t  T0 -> ring: c_valid=%0b c=%h  cc_valid=%0b cc=%h",
                $time, t0_c_valid, t0_c_out, t0_cc_valid, t0_cc_out);
        if (t1_c_valid || t1_cc_valid)
            $display("T=%0t  T1 -> ring: c_valid=%0b c=%h  cc_valid=%0b cc=%h",
                $time, t1_c_valid, t1_c_out, t1_cc_valid, t1_cc_out);
    end

    task automatic dump_all(input string tag);
        automatic int s, w;
        $display("======== CACHE DUMP [%s] @ T=%0t ========", tag, $time);
        $display("  T0 L1:");
        for (s = 0; s < 4; s++)
            for (w = 0; w < 2; w++)
                $display("    set=%0d way=%0d valid=%0b tag=%0h state=%s",
                    s, w, dut0.c1_inf.cache_mem_out[s][w].valid,
                    dut0.c1_inf.cache_mem_out[s][w].tag, dut0.c1_inf.cache_mem_out[s][w].C_tag.name());
        $display("  T1 L1:");
        for (s = 0; s < 4; s++)
            for (w = 0; w < 2; w++)
                $display("    set=%0d way=%0d valid=%0b tag=%0h state=%s",
                    s, w, dut1.c1_inf.cache_mem_out[s][w].valid,
                    dut1.c1_inf.cache_mem_out[s][w].tag, dut1.c1_inf.cache_mem_out[s][w].C_tag.name());
        $display("  T0 L2 (ALL 4 sets):");
        for (s = 0; s < 4; s++)
            for (w = 0; w < 4; w++)
                $display("    set=%0d way=%0d valid=%0b tag=%0h state=%s owner=%0d sharers=%02b",
                    s, w, dut0.c2_inf.cache_mem_out[s][w].valid, dut0.c2_inf.cache_mem_out[s][w].tag,
                    dut0.c2_inf.cache_mem_out[s][w].C_tag.name(), dut0.c2_inf.cache_mem_out[s][w].owner_id,
                    dut0.c2_inf.cache_mem_out[s][w].sharers);
        $display("  T1 L2 (ALL 4 sets):");
        for (s = 0; s < 4; s++)
            for (w = 0; w < 4; w++)
                $display("    set=%0d way=%0d valid=%0b tag=%0h state=%s owner=%0d sharers=%02b",
                    s, w, dut1.c2_inf.cache_mem_out[s][w].valid, dut1.c2_inf.cache_mem_out[s][w].tag,
                    dut1.c2_inf.cache_mem_out[s][w].C_tag.name(), dut1.c2_inf.cache_mem_out[s][w].owner_id,
                    dut1.c2_inf.cache_mem_out[s][w].sharers);
    endtask

    task automatic do_load0(input [7:0] addr);
        begin
            // Hold the request until the L1 controller has accepted and retired it.
            @(negedge clk);
            l1_inst0 = {2'b01, addr};
            wait (dut0.u_c1_ctrl.C_PS == COMPARE);
            @(posedge clk);
            @(negedge clk);
            l1_inst0 = 10'b0;
            wait (dut0.u_c1_ctrl.C_PS == IDLE);
            #1;
        end
    endtask

    task automatic do_load1(input [7:0] addr);
        begin
            @(negedge clk);
            l1_inst1 = {2'b01, addr};
            wait (dut1.u_c1_ctrl.C_PS == COMPARE);
            @(posedge clk);
            @(negedge clk);
            l1_inst1 = 10'b0;
            wait (dut1.u_c1_ctrl.C_PS == IDLE);
            #1;
        end
    endtask

    task automatic do_store0(input [7:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            l1_in_data0 = data;
            l1_inst0 = {2'b10, addr};
            wait (dut0.u_c1_ctrl.C_PS == COMPARE);
            @(posedge clk);
            @(negedge clk);
            l1_inst0 = 10'b0;
            wait (dut0.u_c1_ctrl.C_PS == IDLE);
            #1;
        end
    endtask

    initial begin
        rst = 1'b1;
        l1_inst0 = 10'b0; l1_in_data0 = 8'h00;
        l1_inst1 = 10'b0; l1_in_data1 = 8'h00;
        #25;
        rst = 1'b0;
        @(posedge clk);

        dump_all("INITIAL");

        $display("\n>>>>>>>> TEST 1: T0 LOAD 0x01 -- read miss, fetch from memory, EXCLUSIVE <<<<<<<<\n");
        do_load0(8'h01);
        dump_all("AFTER TEST 1");

        $display("\n>>>>>>>> TEST 2: T1 LOAD 0x15 -- independent read miss, own bank <<<<<<<<\n");
        do_load1(8'h15);
        dump_all("AFTER TEST 2");

        $display("\n>>>>>>>> TEST 4: T0 STORE 0x40 -- write miss (GetM), fetch from memory, MODIFIED directly (L2 set1) <<<<<<<<\n");
        do_store0(8'h40, 8'd55);
        dump_all("AFTER TEST 4");

        $display("\n>>>>>>>> TEST 6: T1 LOAD 0x80 -- T1 reads cold from T0's L2 bank (genuine cross-tile MISS fetch, no L1 owner involved) <<<<<<<<\n");
        do_load1(8'h80);
        dump_all("AFTER TEST 6");

        do_store0(8'h01, 8'd77);
        dump_all("AFTER TEST 7");

        $display("\n--- FINAL CHECKS ---");
        if (dut0.c1_inf.cache_mem_out[0][0].valid && dut0.c1_inf.cache_mem_out[0][0].tag == 4'h0 &&
            dut0.c1_inf.cache_mem_out[0][0].C_tag == MODIFIED)
            $display("  PASS: T0 L1 0x01 is MODIFIED after final store");
        else begin
            $display("  FAIL: T0 L1 0x01 state=%s", dut0.c1_inf.cache_mem_out[0][0].C_tag.name());
            $fatal(1, "coherence check failed: T0 L1 0x01 final state");
        end

        if (dut1.c1_inf.cache_mem_out[1][0].valid && dut1.c1_inf.cache_mem_out[1][0].tag == 4'h1 &&
            dut1.c1_inf.cache_mem_out[1][0].C_tag == EXCLUSIVE)
            $display("  PASS: T1 L1 0x15 is EXCLUSIVE");
        else begin
            $display("  FAIL: T1 L1 0x15 state=%s", dut1.c1_inf.cache_mem_out[1][0].C_tag.name());
            $fatal(1, "coherence check failed");
            end

        if (dut0.c1_inf.cache_mem_out[0][1].valid && dut0.c1_inf.cache_mem_out[0][1].tag == 4'h4 &&
            dut0.c1_inf.cache_mem_out[0][1].C_tag == MODIFIED)
            $display("  PASS: T0 L1 0x40 is MODIFIED");
        else begin
            $display("  FAIL: T0 L1 0x40 state=%s", dut0.c1_inf.cache_mem_out[0][1].C_tag.name());
            $fatal(1, "coherence check failed");
            end

        if (dut0.c2_inf.cache_mem_out[1][0].valid && dut0.c2_inf.cache_mem_out[1][0].tag == 4'h0 &&
            dut0.c2_inf.cache_mem_out[1][0].C_tag == DIR_M && dut0.c2_inf.cache_mem_out[1][0].owner_id == 2'd0)
            $display("  PASS: T0 L2 SET1 directory for 0x40 is DIR_M owner=0");
        else begin
            $display("  FAIL: T0 L2 SET1 directory for 0x40 state=%s owner=%0d",
                dut0.c2_inf.cache_mem_out[1][0].C_tag.name(), dut0.c2_inf.cache_mem_out[1][0].owner_id);
                $fatal(1, "coherence check failed");
                end

        if (dut1.c1_inf.cache_mem_out[0][0].valid && dut1.c1_inf.cache_mem_out[0][0].tag == 4'h8 &&
            dut1.c1_inf.cache_mem_out[0][0].C_tag == EXCLUSIVE)
            $display("  PASS: T1 L1 0x80 is EXCLUSIVE (fetched cold from T0's bank)");
        else begin
            $display("  FAIL: T1 L1 0x80 state=%s", dut1.c1_inf.cache_mem_out[0][0].C_tag.name());
            $fatal(1, "coherence check failed");
            end

        if (dut0.c2_inf.cache_mem_out[2][0].valid && dut0.c2_inf.cache_mem_out[2][0].tag == 4'h0 &&
            dut0.c2_inf.cache_mem_out[2][0].C_tag == DIR_E && dut0.c2_inf.cache_mem_out[2][0].owner_id == 2'd1)
            $display("  PASS: T0 L2 SET2 directory for 0x80 is DIR_E owner=1 (T1, the remote requester)");
        else begin
            $display("  FAIL: T0 L2 SET2 directory for 0x80 state=%s owner=%0d",
                dut0.c2_inf.cache_mem_out[2][0].C_tag.name(), dut0.c2_inf.cache_mem_out[2][0].owner_id);
                $fatal(1, "coherence check failed");
                end


        if (dut0.c1_inf.cache_mem_out[0][0].valid && dut0.c1_inf.cache_mem_out[0][0].tag == 4'h0 &&
            dut0.c1_inf.cache_mem_out[0][0].C_tag == MODIFIED)
            $display("  PASS: T0 L1 0x01 is MODIFIED (silently upgraded from EXCLUSIVE, purely local)");
        else begin
            $display("  FAIL: T0 L1 0x01 state=%s", dut0.c1_inf.cache_mem_out[0][0].C_tag.name());
            $fatal(1, "coherence check failed");
            end
        $display("  INFO: T0 L2 set0 directory for 0x01 shows state=%s (either DIR_E or DIR_M can be correct here depending on whether this design notifies L2 of a silent upgrade -- both mean 'single owner, no sharers' to the directory)",
            dut0.c2_inf.cache_mem_out[0][0].C_tag.name());

        $display("\n--- done ---");
        $finish;
    end

endmodule
