import l2_cache_pkg::*;
import L1_cache_mem::*;

module mem_tap #(parameter logic [2:0] MEM_ID = 3'd4) (
    input logic clk,
    input logic rst,


    input  logic         l2_resp_valid,
    input  l2_nic_pkt_t  l2_resp_pkt,
    output logic         l2_resp_ready,


    output logic         l2_req_valid,
    output l2_nic_pkt_t  l2_req_pkt,


    output logic         nic_out_valid,
    output l2_nic_pkt_t  nic_out_pkt,
    input  logic         nic_out_ready,
    input  logic         nic_in_valid,
    input  l2_nic_pkt_t  nic_in_pkt
);

    logic is_mem_req;
    assign is_mem_req = l2_resp_valid && (l2_resp_pkt.msg == NMSG_MEM_REQ) &&
                         (l2_resp_pkt.dest_id == MEM_ID);


    assign nic_out_valid = l2_resp_valid && !is_mem_req;
    assign nic_out_pkt   = l2_resp_pkt;
    assign l2_resp_ready = is_mem_req ? 1'b1 : nic_out_ready;


    logic [7:0] fake_mem [0:255];
    logic       mem_resp_pending;
    logic [7:0] mem_resp_data;
    logic [2:0] mem_resp_dest;

    task automatic preload(input logic [7:0] addr, input logic [7:0] val);
        fake_mem[addr] = val;
    endtask

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_resp_pending <= 1'b0;
        end
        else begin
            if (mem_resp_pending)
                mem_resp_pending <= 1'b0;
            if (is_mem_req) begin
                if (l2_resp_pkt.we)
                    fake_mem[l2_resp_pkt.addr] <= l2_resp_pkt.data;
                else
                    mem_resp_data <= fake_mem[l2_resp_pkt.addr];
                mem_resp_dest    <= l2_resp_pkt.src_id;
                mem_resp_pending <= 1'b1;
            end
        end
    end
    always_comb begin
        if (mem_resp_pending) begin
            l2_req_valid = 1'b1;
            l2_req_pkt   = '{msg: NMSG_MEM_DATA, we: 1'b0, is_exclusive_in: 1'b0,
                              addr: 8'b0, data: mem_resp_data,
                              src_id: MEM_ID, dest_id: mem_resp_dest};
        end
        else begin
            l2_req_valid = nic_in_valid;
            l2_req_pkt   = nic_in_pkt;
        end
    end

endmodule
