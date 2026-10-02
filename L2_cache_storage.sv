import l2_cache_pkg::*;

module L2_cache_storage(L2_cache.L2_cache_storage_mb c2_inf);
l2_cache_line_t cache_mem[0:3][0:3];   // 4 sets, 4 ways -- fixed

always_comb
begin
 c2_inf.cache_mem_out = cache_mem;
end

always_ff @(posedge c2_inf.clk or posedge c2_inf.rst)
begin
  if(c2_inf.rst)
    begin
      cache_mem <= '{'{'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0}},// just for test case
                '{'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0}},
                '{'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0}},
                '{'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0},'{valid: 1'b0, C_tag: DIR_I, tag: 4'b0,sharers: 4'b0, owner_id: 2'b0, data: 8'b0}}};
    end
  else
    begin
      if(c2_inf.write_en)
        begin
           cache_mem[c2_inf.set_idx][c2_inf.way_sel].valid    <= c2_inf.update_line[22];
           cache_mem[c2_inf.set_idx][c2_inf.way_sel].C_tag    <= dir_state_t'(c2_inf.update_line[21:18]);
           cache_mem[c2_inf.set_idx][c2_inf.way_sel].tag      <= c2_inf.update_line[17:14];
           cache_mem[c2_inf.set_idx][c2_inf.way_sel].sharers  <= c2_inf.update_line[13:10];
           cache_mem[c2_inf.set_idx][c2_inf.way_sel].owner_id <= c2_inf.update_line[9:8];
           cache_mem[c2_inf.set_idx][c2_inf.way_sel].data     <= c2_inf.update_line[7:0];
        end
    end
end
endmodule
