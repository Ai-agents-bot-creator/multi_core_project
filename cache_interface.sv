import L1_cache_mem::*;

interface cache_v1();
    logic clk,rst;
    logic write_en;
    logic [7:0]in_data;
    logic [7:0]Data_out;
    logic [3:0]tag;
    logic [1:0]set_idx;
    logic [1:0]lru_id;
    logic way_sel;
    logic [16:0]update_line;
    l1_cache_line_t cache_mem_out[0:3][0:1];
    logic update_lru;
    logic lru_way;
    logic [9:0]inst;
    l1_msg_out_t msg_req_out;
    l1_msg_in_t msg_req_in;
    logic [7:0]req_addr_in;
    logic [7:0]req_data_in;
    logic [7:0]req_addr_out;
    logic [7:0]req_data_out;
    logic [1:0]peer_id_in;
    logic [1:0]peer_id_out;
    logic       is_exclusive_in;

    modport cache_storage_mb(
        input clk,rst,write_en,set_idx,way_sel,update_line,
        output cache_mem_out
    );

    modport cache_controller_mb(
        input  clk,rst,inst,msg_req_in,req_addr_in,req_data_in,lru_way,in_data,
               cache_mem_out,peer_id_in,is_exclusive_in,
        output write_en,way_sel,update_lru,update_line,Data_out,lru_id,
               msg_req_out,req_addr_out,req_data_out,peer_id_out,
               set_idx
    );
    modport cache_lru_mb(
    input clk,rst,lru_id,update_lru,
    output lru_way
);
endinterface
