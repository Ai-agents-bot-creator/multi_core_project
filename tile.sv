import L1_cache_mem::*;
import l2_cache_pkg::*;

module tile_top #(
    parameter logic [1:0] MY_BANK_ID = 2'd0
) (
    input logic clk,
    input logic rst,

    output logic [7:0]  l1_data_out,
    input  logic [9:0]  l1_inst,
    input  logic [7:0]  l1_in_data,

    input  logic [31:0] c_in,
    input  logic         c_wr,
    output logic [31:0] c_out,
    output logic         c_out_valid,
    input  logic [31:0] cc_in,
    input  logic         cc_wr,
    output logic [31:0] cc_out,
    output logic         cc_out_valid
);

    cache_v1 c1_inf();
    assign c1_inf.clk = clk;
    assign c1_inf.rst = rst;
    assign c1_inf.inst = l1_inst;
    assign c1_inf.in_data = l1_in_data;
    assign l1_data_out = c1_inf.Data_out;

    cache_controller u_c1_ctrl (.c1_inf(c1_inf.cache_controller_mb));
    cache_storage     u_c1_store(.c1_inf(c1_inf.cache_storage_mb));
    cache_lru         u_c1_lru  (.c1_inf(c1_inf.cache_lru_mb));


    L2_cache c2_inf();
    assign c2_inf.clk = clk;
    assign c2_inf.rst = rst;

    l2_cache_controller #(.MY_BANK_ID(MY_BANK_ID)) u_c2_ctrl (.c2_inf(c2_inf.L2_cache_controller_mb));
    L2_cache_storage                                u_c2_store(.c2_inf(c2_inf.L2_cache_storage_mb));


    logic         bypass_valid;
    l2_nic_pkt_t  bypass_pkt;

    logic         mem_req_valid;
    l2_nic_pkt_t  mem_req_pkt;


    l1_msg_out_t mux_to_l2_msg;
    logic [7:0]  mux_to_l2_addr, mux_to_l2_data;

    mux #(.MY_BANK_ID(MY_BANK_ID)) u_mux (
        .clk(clk), .rst(rst),
        .l1_msg_req_out(c1_inf.msg_req_out),
        .l1_req_addr_out(c1_inf.req_addr_out),
        .l1_req_data_out(c1_inf.req_data_out),
        .l1_peer_id_out(c1_inf.peer_id_out),
        .l2_l1_msg_req_in(mux_to_l2_msg),
        .l2_req_addr_out(mux_to_l2_addr),
        .l2_req_data_out(mux_to_l2_data),
        .bypass_valid(bypass_valid),
        .bypass_pkt(bypass_pkt),
        .l2_l1_data_o(c2_inf.l2_l1_data_o),
        .nic_in_valid(mem_req_valid),
        .nic_in_pkt(mem_req_pkt),
        .l1_msg_req_in(c1_inf.msg_req_in),
        .l1_is_exclusive_in(c1_inf.is_exclusive_in),
        .l1_req_data_in(c1_inf.req_data_in),
        .l1_req_addr_in(c1_inf.req_addr_in),
        .l1_peer_id_in(c1_inf.peer_id_in)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            c2_inf.l1_msg_req_in <= MSG_ACK;
            c2_inf.req_addr_out  <= '0;
            c2_inf.req_data_out  <= '0;
        end
        else begin
            c2_inf.l1_msg_req_in <= mux_to_l2_msg;
            c2_inf.req_addr_out  <= mux_to_l2_addr;
            c2_inf.req_data_out  <= mux_to_l2_data;
        end
    end


    logic         combined_resp_valid;
    l2_nic_pkt_t  combined_resp_pkt;
    always_comb begin
        if (c2_inf.resp_valid_o) begin
            combined_resp_valid = 1'b1;
            combined_resp_pkt   = c2_inf.resp_nic_data_o;
        end
        else begin
            combined_resp_valid = bypass_valid;
            combined_resp_pkt   = bypass_pkt;
        end
    end

    logic         tap_to_nic_valid;
    l2_nic_pkt_t  tap_to_nic_pkt;
    logic         nic_ready_to_tap;
    logic         nic_to_tap_valid;
    l2_nic_pkt_t  nic_to_tap_pkt;

    mem_tap #(.MEM_ID(3'd4)) u_mem_tap (
        .clk(clk), .rst(rst),
        .l2_resp_valid(combined_resp_valid), .l2_resp_pkt(combined_resp_pkt),
        .l2_resp_ready(c2_inf.resp_ready_i),
        .l2_req_valid(mem_req_valid), .l2_req_pkt(mem_req_pkt),
        .nic_out_valid(tap_to_nic_valid), .nic_out_pkt(tap_to_nic_pkt), .nic_out_ready(nic_ready_to_tap),
        .nic_in_valid(nic_to_tap_valid), .nic_in_pkt(nic_to_tap_pkt)
    );


    assign c2_inf.req_valid_i   = mem_req_valid;
    assign c2_inf.req_nic_pkt_i = mem_req_pkt;


    logic router_ready_to_nic;
    logic nic_valid_to_router;
    logic [31:0] nic_data_to_router;
    logic router_valid_to_nic;
    logic [31:0] router_data_to_nic;

    nic_top u_nic (
        .clk(clk), .rst(rst),
        .l2_resp_valid(tap_to_nic_valid), .l2_resp_pkt(tap_to_nic_pkt), .l2_resp_ready(nic_ready_to_tap),
        .l2_req_valid(nic_to_tap_valid), .l2_req_pkt(nic_to_tap_pkt),
        .l2_req_ready(1'b1),   // no backpressure into mem_tap/L2 (documented simplification)
        .router_ready(router_ready_to_nic),
        .router_valid_out(nic_valid_to_router), .router_data_out(nic_data_to_router),
        .router_valid_in(router_valid_to_nic), .router_data_in(router_data_to_nic),
        .fifo_full(), .fifo_empty()
    );


    logic l_out_valid_unused;

    router_top u_router (
        .clk(clk), .rst(rst),
        .rid(MY_BANK_ID),
        .l_in(nic_data_to_router), .l_wr(nic_valid_to_router),
        .c_in(c_in), .c_wr(c_wr),
        .cc_in(cc_in), .cc_wr(cc_wr),
        .l_out(router_data_to_nic),
        .c_out(c_out),
        .cc_out(cc_out),
        .dbg_l_dest(), .dbg_c_dest(), .dbg_cc_dest(),
        .dbg_l_rt(), .dbg_c_rt(), .dbg_cc_rt(),
        .dbg_l_cw(), .dbg_l_ccw(), .dbg_c_cw(), .dbg_c_ccw(), .dbg_cc_cw(), .dbg_cc_ccw(),
        .l_out_valid(router_valid_to_nic), .c_out_valid(c_out_valid), .cc_out_valid(cc_out_valid)
    );

    assign router_ready_to_nic = 1'b1;

endmodule
