import L1_cache_mem::*;
import l2_cache_pkg::*;

module mux #(parameter logic [1:0] MY_BANK_ID = 2'd0) (
    input  logic         clk,
    input  logic         rst,


    input  l1_msg_out_t l1_msg_req_out,
    input  logic [7:0]  l1_req_addr_out,
    input  logic [7:0]  l1_req_data_out,

    input  logic [1:0]  l1_peer_id_out,

    //  to local L2
    output l1_msg_out_t l2_l1_msg_req_in,
    output logic [7:0]  l2_req_addr_out,
    output logic [7:0]  l2_req_data_out,

    //  to NIC
    output logic         bypass_valid,
    output l2_nic_pkt_t  bypass_pkt,

    // from local L2
    input  l2_li_data_t  l2_l1_data_o,

    //from NIC
    input  logic         nic_in_valid,
    input  l2_nic_pkt_t   nic_in_pkt,

    //  to local L1
    output l1_msg_in_t   l1_msg_req_in,
    output logic         l1_is_exclusive_in,
    output logic [7:0]   l1_req_data_in,

    output logic [7:0]   l1_req_addr_in,

    output logic [1:0]   l1_peer_id_in
);

    logic is_fresh_request, is_local;
    assign is_fresh_request = (l1_msg_req_out == MSG_GETS) || (l1_msg_req_out == MSG_GETM) ||
                               (l1_msg_req_out == MSG_PUTM) || (l1_msg_req_out == MSG_PUTE);
    assign is_local = (l1_req_addr_out[5:4] == MY_BANK_ID);

    logic is_fwd_remote_reply;
    assign is_fwd_remote_reply = 1'b0;

    logic sent_this_req;
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            sent_this_req <= 1'b0;
        else if (!is_fresh_request)
            sent_this_req <= 1'b0;
        else if (is_fresh_request && !is_local && !sent_this_req)
            sent_this_req <= 1'b1;
    end

    logic sent_this_fwd;
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            sent_this_fwd <= 1'b0;
        else if (!is_fwd_remote_reply)
            sent_this_fwd <= 1'b0;
        else if (is_fwd_remote_reply && !sent_this_fwd)
            sent_this_fwd <= 1'b1;
    end

    function automatic l2_nic_msg_t l1_to_nic_msg(l1_msg_out_t m);
        case (m)
            MSG_GETS: return NMSG_GETS;
            MSG_GETM: return NMSG_GETM;
            MSG_PUTE: return NMSG_PUTE;
            MSG_PUTM: return NMSG_PUTM;
            default:  return NMSG_NONE;
        endcase
    endfunction

    always_comb begin
        l2_l1_msg_req_in = MSG_ACK;
        l2_req_addr_out  = l1_req_addr_out;
        l2_req_data_out  = l1_req_data_out;
        bypass_valid     = 1'b0;
        bypass_pkt       = '0;
        if (is_fresh_request && !is_local && !sent_this_req) begin
            bypass_valid = 1'b1;
            bypass_pkt   = '{msg: l1_to_nic_msg(l1_msg_req_out), we: 1'b0, is_exclusive_in: 1'b0,
                              addr: l1_req_addr_out, data: l1_req_data_out,
                              src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, l1_req_addr_out[5:4]}};
        end
        else if (is_fwd_remote_reply && !sent_this_fwd) begin
            bypass_valid = 1'b1;
            bypass_pkt   = '{msg: NMSG_DATAFWD, we: 1'b0, is_exclusive_in: 1'b0,
                              addr: l1_req_addr_out, data: l1_req_data_out,
                              src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, l1_peer_id_out}};
        end
        else if (!(is_fresh_request && !is_local) && !is_fwd_remote_reply) begin
            l2_l1_msg_req_in = l1_msg_req_out;
        end
    end

    always_comb begin
        if (nic_in_valid && (nic_in_pkt.msg == NMSG_DATA || nic_in_pkt.msg == NMSG_DATAFWD)) begin
            l1_msg_req_in      = MSG_DATA;
            l1_is_exclusive_in = nic_in_pkt.is_exclusive_in;
            l1_req_data_in     = nic_in_pkt.data;
            l1_req_addr_in     = nic_in_pkt.addr;
            l1_peer_id_in      = 2'b00;
        end
        else begin
            l1_msg_req_in      = l2_l1_data_o.msg_in;
            l1_is_exclusive_in = l2_l1_data_o.is_exclusive_in;
            l1_req_data_in     = l2_l1_data_o.data;
            l1_req_addr_in     = l2_l1_data_o.addr;
            l1_peer_id_in      = l2_l1_data_o.requester_id;
        end
    end

endmodule
