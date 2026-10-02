import L1_cache_mem::*;

interface Mux_inf();
l1_msg_out_t msg_req_out;
logic [7:0]req_addr_out;
logic [7:0]req_data_out;
logic [1:0]peer_id_out;
l1_msg_out_t NIC_msg_req;
logic [7:0]NIC_req_addr;
logic [7:0]NIC_req_data;
logic [1:0]NIC_peer_id_out;
l1_msg_out_t L2_msg_req;
logic [7:0]L2_req_addr;
logic [7:0]L2_req_data;
modport mux_mb(
    input msg_req_out,req_data_out,req_addr_out,peer_id_out,
    output NIC_msg_req,NIC_req_addr,NIC_req_data,NIC_peer_id_out,L2_msg_req,L2_req_addr,L2_req_data
);
endinterface
