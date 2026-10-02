// FIFO
module fifo_in (
input logic clk,
input logic rst,
input logic [31:0] din,
input logic wr,
input logic rd,
output logic [31:0] dout,
output logic full,
output logic empty
);
logic [31:0] mem [0:15];
logic [3:0] wptr;
logic [3:0] rptr;
logic [4:0] cnt;
always_ff @(posedge clk) begin
if (rst) begin
 wptr <='0;
 rptr <='0;
 cnt <='0;
 dout <='0;
  end
  else begin
 if (wr && !full) begin
    mem[wptr] <= din;
    wptr <= wptr + 1;
 end
 if (rd && !empty) begin
    dout <= mem[rptr];
    rptr <= rptr + 1;
  end
unique case ({wr && !full, rd && !empty})
  2'b10: cnt <= cnt + 1;
  2'b01: cnt <= cnt - 1;
  default: cnt <= cnt;
  endcase
  end
end
assign full = (cnt == 16);
assign empty = (cnt == 0);
endmodule

//FLIT DECODER
module flit_dec (
input logic [31:0] flit,
output logic [1:0] dest
);
assign dest = flit[31:30];
endmodule

//  ROUTE COMPUTATION
module route_comp (
input logic [1:0] cur,
input logic [1:0] dest,
output logic [1:0] route,
output logic [2:0] cw_dis,
output logic [2:0] ccw_dis
);
localparam logic [1:0] LOC = 2'b00;
localparam logic [1:0] CW = 2'b01;
localparam logic [1:0] CCW = 2'b10;
always_comb begin
  route = LOC;
  cw_dis = '0;
  ccw_dis = '0;
  if (cur == dest) begin
  route = LOC;
  end
  else begin
  cw_dis  = (dest - cur + 4) % 4;
  ccw_dis = (cur - dest + 4) % 4;
  if (cw_dis <= ccw_dis)
      route = CW;
  else
      route = CCW;
    end
end
endmodule

//  SWITCH CONTROL
module sw_ctrl (
input logic [1:0] l_rt,
input logic [1:0] c_rt,
input logic [1:0] cc_rt,
output logic [1:0] l_sel,
output logic [1:0] c_sel,
output logic [1:0] cc_sel
);
localparam logic [1:0] LOC = 2'b00;
localparam logic [1:0] CW = 2'b01;
localparam logic [1:0] CCW = 2'b10;
localparam logic [1:0] NONE = 2'b11;
always_comb begin
  l_sel = NONE;
  c_sel = NONE;
  cc_sel = NONE;
  if (l_rt == LOC)
    l_sel = 2'b00;
  else if (c_rt == LOC)
    l_sel = 2'b01;
  else if (cc_rt == LOC)
    l_sel = 2'b10;
  if (l_rt == CW)
    c_sel = 2'b00;
  else if (c_rt == CW)
    c_sel = 2'b01;
  else if (cc_rt == CW)
    c_sel = 2'b10;
  if (l_rt == CCW)
    cc_sel = 2'b00;
  else if (c_rt == CCW)
    cc_sel = 2'b01;
  else if (cc_rt == CCW)
    cc_sel = 2'b10;
end
endmodule

//  CROSSBAR
module xbar (
    input logic [31:0] l_in,
    input logic [31:0] c_in,
    input logic [31:0] cc_in,
    input logic [1:0] l_sel,
    input logic [1:0] c_sel,
    input logic [1:0] cc_sel,
    output logic [31:0] l_out,
    output logic [31:0] c_out,
    output logic [31:0] cc_out
);
always_comb begin
    case (l_sel)
    2'b00: l_out = l_in;
    2'b01: l_out = c_in;
    2'b10: l_out = cc_in;
    default: l_out = '0;
    endcase
    case (c_sel)
    2'b00: c_out = l_in;
    2'b01: c_out = c_in;
    2'b10: c_out = cc_in;
    default: c_out = '0;
    endcase
    case (cc_sel)
    2'b00: cc_out = l_in;
    2'b01: cc_out = c_in;
    2'b10: cc_out = cc_in;
    default: cc_out = '0;
    endcase
end
endmodule

// ROUTER TOP
module router_top (
input logic clk,
input logic rst,
input logic [1:0] rid,
input logic [31:0] l_in,
input logic l_wr,
input logic [31:0] c_in,
input logic c_wr,
input logic [31:0] cc_in,
input logic cc_wr,
output logic [31:0] l_out,
output logic [31:0] c_out,
output logic [31:0] cc_out,
output logic [1:0] dbg_l_dest,
output logic [1:0] dbg_c_dest,
output logic [1:0] dbg_cc_dest,
output logic [1:0] dbg_l_rt,
output logic [1:0] dbg_c_rt,
output logic [1:0] dbg_cc_rt,
output logic [2:0] dbg_l_cw,
output logic [2:0] dbg_l_ccw,
output logic [2:0] dbg_c_cw,
output logic [2:0] dbg_c_ccw,
output logic [2:0] dbg_cc_cw,
output logic [2:0] dbg_cc_ccw,

output logic l_out_valid, c_out_valid, cc_out_valid
);
logic [31:0] l_data;
logic [31:0] c_data;
logic [31:0] cc_data;
logic l_full, l_empty;
logic c_full, c_empty;
logic cc_full, cc_empty;
logic l_rd, c_rd, cc_rd;
assign l_rd = !l_empty;
assign c_rd = !c_empty;
assign cc_rd = !cc_empty;
logic [1:0] l_dest, c_dest, cc_dest;
logic [1:0] l_rt, c_rt, cc_rt;
logic [1:0] l_rt_g, c_rt_g, cc_rt_g;
logic [2:0] l_cw, l_ccw;
logic [2:0] c_cw, c_ccw;
logic [2:0] cc_cw, cc_ccw;
logic [1:0] l_sel, c_sel, cc_sel;
fifo_in f0 (
.clk(clk),
.rst(rst),
.din(l_in),
.wr(l_wr),
.rd(l_rd),
.dout(l_data),
.full(l_full),
.empty(l_empty)
);
fifo_in f1 (
.clk(clk),
.rst(rst),
.din(c_in),
.wr(c_wr),
.rd(c_rd),
.dout(c_data),
.full(c_full),
.empty(c_empty)
);
fifo_in f2 (
.clk(clk),
.rst(rst),
  .din(cc_in),
.wr(cc_wr),
.rd(cc_rd),
.dout(cc_data),
.full(cc_full),
.empty(cc_empty)
);
flit_dec d0 (
.flit(l_data),
.dest(l_dest)
);
flit_dec d1 (
.flit(c_data),
.dest(c_dest)
);
flit_dec d2 (
.flit(cc_data),
.dest(cc_dest)
);
route_comp r0 (
.cur(rid),
.dest(l_dest),
.route(l_rt),
.cw_dis(l_cw),
.ccw_dis(l_ccw)
);
route_comp r1 (
.cur(rid),
.dest(c_dest),
.route(c_rt),
.cw_dis(c_cw),
.ccw_dis(c_ccw)
);
route_comp r2 (
.cur(rid),
.dest(cc_dest),
.route(cc_rt),
.cw_dis(cc_cw),
.ccw_dis(cc_ccw)
);

logic l_rd_d1, c_rd_d1, cc_rd_d1;
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        l_rd_d1  <= 1'b0;
        c_rd_d1  <= 1'b0;
        cc_rd_d1 <= 1'b0;
    end
    else begin
        l_rd_d1  <= l_rd;
        c_rd_d1  <= c_rd;
        cc_rd_d1 <= cc_rd;
    end
end
assign l_rt_g  = l_rd_d1  ? l_rt  : 2'b11;
assign c_rt_g  = c_rd_d1  ? c_rt  : 2'b11;
assign cc_rt_g = cc_rd_d1 ? cc_rt : 2'b11;

sw_ctrl s0 (
   .l_rt(l_rt_g),
  .c_rt(c_rt_g),
.cc_rt(cc_rt_g),
  .l_sel(l_sel),
.c_sel(c_sel),
.cc_sel(cc_sel)
);
xbar x0 (
.l_in(l_data),
.c_in(c_data),
.cc_in(cc_data),
.l_sel(l_sel),
.c_sel(c_sel),
.cc_sel(cc_sel),
.l_out(l_out),
.c_out(c_out),
.cc_out(cc_out)
);
assign dbg_l_dest = l_dest;
assign dbg_c_dest = c_dest;
assign dbg_cc_dest = cc_dest;
assign dbg_l_rt = l_rt;
assign dbg_c_rt = c_rt;
assign dbg_cc_rt = cc_rt;
assign dbg_l_cw = l_cw;
assign dbg_l_ccw = l_ccw;
assign dbg_c_cw = c_cw;
assign dbg_c_ccw = c_ccw;
assign dbg_cc_cw = cc_cw;
assign dbg_cc_ccw = cc_ccw;
assign l_out_valid  = (l_sel  != 2'b11);
assign c_out_valid  = (c_sel  != 2'b11);
assign cc_out_valid = (cc_sel != 2'b11);
endmodule

// TB
module tb_router;
logic clk;
logic rst;
logic [1:0] rid;
logic [31:0] l_in;
logic l_wr;
logic [31:0] c_in;
logic c_wr;
logic [31:0] cc_in;
logic cc_wr;
logic [31:0] l_out;
logic [31:0] c_out;
logic [31:0] cc_out;
logic [1:0] dbg_l_dest;
logic [1:0] dbg_c_dest;
logic [1:0] dbg_cc_dest;
logic [1:0] dbg_l_rt;
logic [1:0] dbg_c_rt;
logic [1:0] dbg_cc_rt;
logic [2:0] dbg_l_cw;
logic [2:0] dbg_l_ccw;
logic [2:0] dbg_c_cw;
logic [2:0] dbg_c_ccw;
logic [2:0] dbg_cc_cw;
logic [2:0] dbg_cc_ccw;
logic l_out_valid, c_out_valid, cc_out_valid;
router_top dut (
    .clk(clk),
    .rst(rst),
   .rid(rid),
   .l_in(l_in),
   .l_wr(l_wr),
   .c_in(c_in),
   .c_wr(c_wr),
   .cc_in(cc_in),
   .cc_wr(cc_wr),
   .l_out(l_out),
   .c_out(c_out),
   .cc_out(cc_out),
 .dbg_l_dest(dbg_l_dest),
 .dbg_c_dest(dbg_c_dest),
 .dbg_cc_dest(dbg_cc_dest),
 .dbg_l_rt(dbg_l_rt),
 .dbg_c_rt(dbg_c_rt),
 .dbg_cc_rt(dbg_cc_rt),
 .dbg_l_cw(dbg_l_cw),
 .dbg_l_ccw(dbg_l_ccw),
 .dbg_c_cw(dbg_c_cw),
  .dbg_c_ccw(dbg_c_ccw),
  .dbg_cc_cw(dbg_cc_cw),
 .dbg_cc_ccw(dbg_cc_ccw),
 .l_out_valid(l_out_valid), .c_out_valid(c_out_valid), .cc_out_valid(cc_out_valid)
);
always #5 clk = ~clk;

function automatic logic [31:0] mk_flit(logic [1:0] dest, logic [29:0] payload);
    return {dest, payload};
endfunction
task send_l(input logic [31:0] data);
begin
  @(posedge clk);
  l_in = data;
  l_wr = 1;
  @(posedge clk);
  l_wr = 0;
end
endtask
task send_c(input logic [31:0] data);
begin
    @(posedge clk);
    c_in = data;
    c_wr = 1;
    @(posedge clk);
    c_wr = 0;
end
endtask
task send_cc(input logic [31:0] data);
begin
 @(posedge clk);
 cc_in = data;
 cc_wr = 1;
 @(posedge clk);
 cc_wr = 0;
end
endtask
task show_l;
begin
    $display("CURRENT ROUTER = %0d", rid);
    $display("DESTINATION = %0d", dbg_l_dest);
    $display("CW DISTANCE = %0d", dbg_l_cw);
    $display("CCW DISTANCE = %0d", dbg_l_ccw);
    case (dbg_l_rt)
     2'b00: $display("PATH = LOCAL");
      2'b01: $display("PATH = CW");
      2'b10: $display("PATH = CCW");
    endcase
end
endtask
task show_c;
begin
 $display("CURRENT ROUTER = %0d", rid);
 $display("DESTINATION = %0d", dbg_c_dest);
 $display("CW DISTANCE = %0d", dbg_c_cw);
 $display("CCW DISTANCE = %0d", dbg_c_ccw);
 case (dbg_c_rt)
  2'b00: $display("PATH = LOCAL");
  2'b01: $display("PATH = CW");
   2'b10: $display("PATH = CCW");
 endcase
end
endtask
task show_cc;
begin
  $display("CURRENT ROUTER = %0d", rid);
  $display("DESTINATION = %0d", dbg_cc_dest);
 $display("CW DISTANCE= %0d", dbg_cc_cw);
  $display("CCW DISTANCE = %0d", dbg_cc_ccw);
 case (dbg_cc_rt)
   2'b00: $display("PATH = LOCAL");
   2'b01: $display("PATH = CW");
   2'b10: $display("PATH = CCW");
  endcase
end
endtask
initial begin
clk = 0;
rst = 1;
 rid = 2'b00;
 l_in = 0;
 c_in = 0;
 cc_in = 0;
 l_wr = 0;
 c_wr = 0;
 cc_wr = 0;
 #20;
 rst = 0;
$display("TEST 1 : LOCAL -> LOCAL");
send_l(mk_flit(2'b00, 30'h3FF));
#20;
show_l();
$display("LOCAL OUT = %h", l_out);#20;
$display("TEST 2 : LOCAL -> CW");
 send_l(mk_flit(2'b01, 30'h2FF));
 #20;
 show_l();
 $display("CW OUT = %h", c_out);
 #20;
 $display("TEST 3 : LOCAL -> CCW");
 send_l(mk_flit(2'b11, 30'h1FF));
 #20;
 show_l();
 $display("CCW OUT = %h", cc_out);
 #20;
 $display("TEST 4 : CW -> LOCAL");
 send_c(mk_flit(2'b00, 30'h0AA));
 #20;
 show_c();
 $display("LOCAL OUT = %h", l_out);
 #20;
 $display("TEST 5 : CCW -> LOCAL");
 send_cc(mk_flit(2'b00, 30'h0BB));
 #20;
 show_cc();
 $display("LOCAL OUT = %h", l_out);
 #20;
 $display("TEST 6 : R0 -> R2");
 send_l(mk_flit(2'b10, 30'h0CC));
  #20;
  show_l();
  $display("CW OUT = %h", c_out);
  #20;
  $display("TEST 7 : MULTIPLE INPUTS");
  fork
 send_l(mk_flit(2'b01, 30'h001));
 send_c(mk_flit(2'b10, 30'h002));
 send_cc(mk_flit(2'b11, 30'h003));
  join
 #30;
$display("LOCAL");
 show_l();
$display("CW");
show_c();
$display("CCW");
show_cc();
$display("LOCAL OUT = %h", l_out);
$display("CW OUT    = %h", c_out);
$display("CCW OUT   = %h", cc_out);
#30;
$display("ROUTER TEST COMPLETED");
#20;
$finish;
end
endmodule
