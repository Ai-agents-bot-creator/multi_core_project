

import L1_cache_mem::*;


module cache_L1_top ();
cache_v1 c1_inf();
l1_cache_line_t cache_mem_out[0:3][0:1];
cache_controller c1(.c1_inf(c1_inf.cache_controller_mb));
cache_storage c2(.c1_inf(c1_inf.cache_storage_mb));
cache_lru c3(.c1_inf(c1_inf.cache_lru_mb));
initial
begin
 c1_inf.clk = 1'b0;
 forever  #10 c1_inf.clk = ~c1_inf.clk;
end
initial begin

  c1_inf.rst = 1'b1;
  #20;
  c1_inf.rst = 1'b0;

  // load miss: set 0, tag 1 -> EXCLUSIVE, data 100
  c1_inf.inst = 10'b0100010010;
  #40;
  c1_inf.is_exclusive_in   = 1'b0;
  c1_inf.msg_req_in = MSG_DATA;
  c1_inf.req_data_in    = 8'd100;
  c1_inf.req_addr_in = 10'b0100010010;
  #100;
c1_inf.inst = 10'b0000000000;
#20;
$display("start of second command");
  // load miss: set 0, tag 2 -> SHARED, data 200
  c1_inf.inst = 10'b0101111000;
  #40;
   c1_inf.is_exclusive_in   = 1'b1;
  c1_inf.msg_req_in = MSG_DATA;
  c1_inf.req_data_in    = 8'd240;
  c1_inf.req_addr_in = 10'b0101111000;
  #100;
  #100;

c1_inf.inst = 10'b0000000000;
#20;
  // store miss: set 0, tag 4
  c1_inf.inst    = 10'b1001000000;
  c1_inf.in_data = 8'd12;
  #20;
  c1_inf.msg_req_in = MSG_DATA;
  c1_inf.req_data_in    = 8'd40;
  c1_inf.req_addr_in = 10'b1001000000;
  #100;

  c1_inf.inst = 10'b0000000000;
  #20;


c1_inf.inst    = 10'b1010000000;
c1_inf.in_data = 8'd64;
#20;
c1_inf.inst = 10'b0000000000;

#20;

c1_inf.req_data_in = 8'd77;
c1_inf.req_addr_in = 10'b1010000000;
#80;
   c1_inf.msg_req_in = MSG_NONE;
  c1_inf.req_data_in    = 8'd40;
  c1_inf.req_addr_in = 10'b1001000000;
 #20;
     c1_inf.msg_req_in = MSG_FWD_GETS;
     c1_inf.peer_id_in = 2'b11;
  c1_inf.req_addr_in = 8'b01000000;
#100;
     c1_inf.msg_req_in = MSG_NONE;
     #100;


  $finish;

end
initial
begin
  $monitor("time = %t,clk = %b, rst = %b,inst = %b,Data_out = %d,cache_mem_out = %p,update_line = %b,C_PS = %d,C_NS = %d,stall = %b,done = %b,write_back = %b,lru_way = %b,write_en = %b,way_sel = %b,fill_pending = %b,msg_req_in = %d,req_addr_in = %b, req_data_in = %d,mag_req_out = %d,req_addr_out = %b,req_data_out = %d,pending_state = %d,peer_id_out = %d",
            $time , c1_inf.clk,c1_inf.rst,c1_inf.inst,c1_inf.Data_out,c1_inf.cache_mem_out,c1_inf.update_line,cache_L1_top.c1.C_PS,cache_L1_top.c1.C_NS,cache_L1_top.c1.stall,cache_L1_top.c1.done,cache_L1_top.c1.write_back,c1_inf.lru_way,c1_inf.write_en,c1_inf.way_sel,cache_L1_top.c1.fill_pending,c1_inf.msg_req_in,c1_inf.req_addr_in,c1_inf.req_data_in,c1_inf.msg_req_out,c1_inf.req_addr_out,c1_inf.req_data_out,cache_L1_top.c1.pending_state,c1_inf.peer_id_out);
end
endmodule
