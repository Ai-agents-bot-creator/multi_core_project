import l2_cache_pkg::*;
import L1_cache_mem::*;

interface L2_cache();
    logic clk, rst;

    // ---- local L1 link (this core's own private L1, no valid/ready -- same
    //      style as cache_v1's single msg_req_in/out) ------------------------
    l1_msg_out_t   l1_msg_req_in;   // whatever local L1 sends this cycle
    logic [7:0]    req_addr_out;    // address accompanying l1_msg_req_in
    logic [7:0]    req_data_out;    // data accompanying l1_msg_req_in
    l2_li_data_t   l2_l1_data_o;    // bundled msg/excl/addr/data sent down to local L1

    // ---- NIC link (bidirectional, either side initiates) --------------------
    // Under Option B, memory is reached over this SAME link (msg=NMSG_MEM_REQ/
    // NMSG_MEM_DATA, dest_id/src_id=MEM_ID) -- there is no separate mem port.
    logic          req_valid_i;
    logic          req_ready_o;
    l2_nic_pkt_t   req_nic_pkt_i;

    logic          resp_valid_o;
    logic          resp_ready_i;
    l2_nic_pkt_t   resp_nic_data_o;

    // ---- storage (mirrors cache_v1's write_en/set_idx/way_sel/update_line) -
    l2_cache_line_t cache_mem_out [0:3][0:3];   // [set][way]
    logic           write_en;
    logic [1:0]     set_idx;
    logic [1:0]     way_sel;
    logic [22:0]    update_line;   // valid(1)+C_tag(4)+tag(4)+sharers(4)+owner_id(2)+data(8)

    modport L2_cache_storage_mb(
        input  clk, rst, write_en, set_idx, way_sel, update_line,
        output cache_mem_out
    );

    // FIX: removed mem_ready_in/mem_rdata_in/mem_req_out/mem_we_out/
    // mem_addr_out/mem_wdata_out -- those signals don't exist on this
    // interface anymore (Option B routes memory traffic over
    // req_nic_pkt_i/resp_nic_data_o instead), so referencing them here
    // was a compile error.
    modport L2_cache_controller_mb(
        input  clk, rst,
               l1_msg_req_in, req_addr_out, req_data_out,
               req_valid_i, req_nic_pkt_i,
               resp_ready_i,
               cache_mem_out,
        output l2_l1_data_o,
               req_ready_o,
               resp_valid_o, resp_nic_data_o,
               write_en, set_idx, way_sel, update_line
    );
endinterface
