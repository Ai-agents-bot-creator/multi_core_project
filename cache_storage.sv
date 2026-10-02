import L1_cache_mem::*;

module cache_storage(cache_v1.cache_storage_mb c1_inf);
//cache c1_inf();
l1_cache_line_t cache_mem[0:3][0:1];
always_comb
begin
 c1_inf.cache_mem_out = cache_mem;
end

always_ff @(posedge c1_inf.clk or posedge c1_inf.rst)
begin
  if (c1_inf.rst)
    begin
       cache_mem <= '{'{'{1'b0,INVALID,4'b0,8'd0},'{1'b0,INVALID,4'b0,8'b0}},// just for test case
                '{'{1'b0,INVALID,4'b0,8'b0},'{1'b0,INVALID,4'b0,8'b0}},
                '{'{1'b0,INVALID,4'b0,8'b0},'{1'b0,INVALID,4'b0,8'b0}},
                '{'{1'b0,INVALID,4'b0,8'b0},'{1'b0,INVALID,4'b0,8'b0}}};
    end
  else
    begin
      if (c1_inf.write_en)
        begin
          cache_mem[c1_inf.set_idx][c1_inf.way_sel].data <= c1_inf.update_line[7:0];
          cache_mem[c1_inf.set_idx][c1_inf.way_sel].tag <= c1_inf.update_line[11:8];
          cache_mem[c1_inf.set_idx][c1_inf.way_sel].valid <= c1_inf.update_line[16];
          cache_mem[c1_inf.set_idx][c1_inf.way_sel].C_tag <= MESI_STATES_t'(c1_inf.update_line[15:12]);
        end
    end
end
endmodule
