import l2_cache_pkg::*;
import L1_cache_mem::*;

// TOP MODULE
module nic_top(
    input logic clk,
    input logic rst,


    input  logic         l2_resp_valid,
    input  l2_nic_pkt_t  l2_resp_pkt,
    output logic         l2_resp_ready,

    output logic         l2_req_valid,
    output l2_nic_pkt_t  l2_req_pkt,
    input  logic         l2_req_ready,

    input  logic router_ready,
    output logic router_valid_out,
    output logic [31:0] router_data_out,
    input  logic router_valid_in,
    input  logic [31:0] router_data_in,

    output logic fifo_full,
    output logic fifo_empty
);
logic [31:0] fifo_data_out;
logic [3:0] fifo_count;
logic fifo_rd_en;
logic fifo_wr_en;
logic [31:0] fifo_data_in;
logic [31:0] packet;
logic packet_valid;
logic [31:0] rx_packet;
logic rx_packet_valid;
logic tx_ready;


assign fifo_wr_en   = l2_resp_valid;
assign fifo_data_in = pack_flit(l2_resp_pkt);
assign l2_resp_ready = !fifo_full;

request_fifo fifo
(
    .clk(clk),
    .rst(rst),
    .wr_en(fifo_wr_en),
    .data_in(fifo_data_in),
    .rd_en(fifo_rd_en),
    .data_out(fifo_data_out),
    .full(fifo_full),
    .empty(fifo_empty),
    .count(fifo_count)
);
packet_generator pg
(
    .clk(clk),
    .rst(rst),
    .fifo_data(fifo_data_out),
    .fifo_valid(~fifo_empty),
    .tx_ready(tx_ready),
    .packet(packet),
    .packet_valid(packet_valid),
    .fifo_rd_en(fifo_rd_en)
);
tx_controller tx
(
    .clk(clk),
    .rst(rst),
    .packet(packet),
    .packet_valid(packet_valid),
    .router_ready(router_ready),
    .router_data(router_data_out),
    .router_valid(router_valid_out),
    .tx_ready(tx_ready)
);
rx_controller rx
(
    .clk(clk),
    .rst(rst),
    .router_valid(router_valid_in),
    .router_data(router_data_in),
    .packet_valid(rx_packet_valid),
    .packet_out(rx_packet)
);
packet_decoder decoder
(
    .clk(clk),
    .rst(rst),
    .packet(rx_packet),
    .packet_valid(rx_packet_valid),
    .decode_valid(l2_req_valid),
    .pkt_out(l2_req_pkt)
);


function automatic logic [31:0] pack_flit(l2_nic_pkt_t p);
    pack_flit = {p.dest_id[1:0], p.src_id[1:0], p.msg, p.we, p.is_exclusive_in,
                 p.addr, p.data, 6'b0};
endfunction

function automatic l2_nic_pkt_t unpack_flit(logic [31:0] f);
    unpack_flit.dest_id          = {1'b0, f[31:30]};
    unpack_flit.src_id           = {1'b0, f[29:28]};
    unpack_flit.msg              = l2_nic_msg_t'(f[27:24]);
    unpack_flit.we               = f[23];
    unpack_flit.is_exclusive_in  = f[22];
    unpack_flit.addr             = f[21:14];
    unpack_flit.data             = f[13:6];
endfunction

endmodule

//FIFO
module request_fifo(
    input  logic clk,
    input  logic rst,
    input  logic wr_en,
    input  logic [31:0] data_in,
    input  logic rd_en,
    output logic [31:0] data_out,
    output logic full,
    output logic empty,
    output logic [3:0] count
);
logic [31:0] mem [0:7];
logic [2:0] wr_ptr;
logic [2:0] rd_ptr;
always_ff @(posedge clk or posedge rst)
begin
    if(rst)
    begin
        wr_ptr <= 3'b000;
        rd_ptr <= 3'b000;
        count <= 4'd0;
        for(int i=0;i<8;i++)
            mem[i] <= 32'd0;
    end
    else
    begin
      case({wr_en && !full, rd_en && !empty})
        2'b10:
        begin
            mem[wr_ptr] <= data_in;
            wr_ptr <= wr_ptr + 1'b1;
            count <= count + 1'b1;
        end
        2'b01:
        begin
            rd_ptr <= rd_ptr + 1'b1;
            count <= count - 1'b1;
        end
        2'b11:
        begin
            mem[wr_ptr] <= data_in;
            wr_ptr <= wr_ptr + 1'b1;
            rd_ptr <= rd_ptr + 1'b1;
            count <= count;
        end
        default:
        begin
            count <= count;
        end
        endcase
    end
end
always_comb
begin
    data_out = mem[rd_ptr];
end
assign empty = (count == 0);
assign full  = (count == 8);
endmodule


module packet_generator(
input logic clk,
input logic rst,
input logic [31:0] fifo_data,
input logic fifo_valid,
input logic tx_ready,
output logic [31:0] packet,
output logic packet_valid,
output logic fifo_rd_en
);
always_ff @(posedge clk or posedge rst)
begin
    if(rst)
    begin
        packet <= 32'd0;
        packet_valid <= 1'b0;
        fifo_rd_en <= 1'b0;
    end
    else
    begin
        packet_valid <= 1'b0;
        fifo_rd_en   <= 1'b0;
        if(fifo_valid && tx_ready)
        begin
            packet       <= fifo_data;
            packet_valid <= 1'b1;
            fifo_rd_en   <= 1'b1;
        end
    end
end
endmodule

module tx_controller(
input logic clk,
input logic rst,
input logic [31:0] packet,
input logic packet_valid,
input logic router_ready,
output logic [31:0] router_data,
output logic router_valid,
output logic tx_ready
);
typedef enum logic [1:0]
{
    IDLE,
    LOAD,
    WAIT_READY,
    SEND

} state_t;
state_t state,next_state;
logic [31:0] packet_reg;
always_ff @(posedge clk or posedge rst)
begin
    if(rst)
        state <= IDLE;
    else
        state <= next_state;
end
always_ff @(posedge clk or posedge rst)
begin
    if(rst)
        packet_reg <= 32'd0;

    else if(state == LOAD)
        packet_reg <= packet;
    end
always_comb
begin
    next_state = state;
    router_valid = 1'b0;
    router_data  = 32'd0;
    case(state)
    IDLE:
    begin
        if(packet_valid)
            next_state = LOAD;
    end
    LOAD:
    begin
        next_state = WAIT_READY;
    end
    WAIT_READY:
    begin
        if(router_ready)
            next_state = SEND;
    end
    SEND:
    begin
        router_valid = 1'b1;
        router_data = packet_reg;
        if(router_ready)
            next_state = IDLE;
    end
    default:
        next_state = IDLE;
endcase
end
assign tx_ready = (state == IDLE);
endmodule

module rx_controller(
    input logic clk,
    input logic rst,
    input  logic router_valid,
    input  logic [31:0] router_data,
    output logic packet_valid,
    output logic [31:0] packet_out
);
always_ff @(posedge clk or posedge rst)
begin
    if(rst)
    begin
        packet_out   <= 32'd0;
        packet_valid <= 1'b0;
    end
    else
    begin
        packet_valid <= 1'b0;
        if(router_valid)
        begin
            packet_out <= router_data;
            packet_valid <= 1'b1;
        end
    end
end
endmodule

module packet_decoder(
    input logic clk,
    input logic rst,
    input logic [31:0] packet,
    input logic packet_valid,
    output logic decode_valid,
    output l2_nic_pkt_t pkt_out
);
import l2_cache_pkg::*;
always_comb
begin
    decode_valid = 1'b0;
    pkt_out = '0;
    if(packet_valid)
    begin
        pkt_out.dest_id         = {1'b0, packet[31:30]};
        pkt_out.src_id          = {1'b0, packet[29:28]};
        pkt_out.msg             = l2_nic_msg_t'(packet[27:24]);
        pkt_out.we              = packet[23];
        pkt_out.is_exclusive_in = packet[22];
        pkt_out.addr            = packet[21:14];
        pkt_out.data            = packet[13:6];
        decode_valid = 1'b1;
    end
end
endmodule
