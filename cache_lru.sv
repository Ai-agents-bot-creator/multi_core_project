module cache_lru(cache_v1.cache_lru_mb c1_inf);
logic [3:0]lru_tag = 4'b0000;
always_ff @(posedge c1_inf.clk or posedge c1_inf.rst)
begin
  if (c1_inf.rst)
    lru_tag <= 4'b0000;
  else if (c1_inf.update_lru)
    case (c1_inf.lru_id)
      2'b00: lru_tag[0] <= ~lru_tag[0];
      2'b01: lru_tag[1] <= ~lru_tag[1];
      2'b10: lru_tag[2] <= ~lru_tag[2];
      default: lru_tag[3] <= ~lru_tag[3];
    endcase
end

always_comb
begin
  case (c1_inf.lru_id)
    2'b00: c1_inf.lru_way = lru_tag[0];
    2'b01: c1_inf.lru_way = lru_tag[1];
    2'b10: c1_inf.lru_way = lru_tag[2];
    default: c1_inf.lru_way = lru_tag[3];
  endcase
end
endmodule
