import L1_cache_mem::*;

module cache_controller(cache_v1.cache_controller_mb c1_inf);

l1_cache_line_t cache_mem_out[0:3][0:1];
C_STATES_t C_NS, C_PS;
logic done = 1'b0;
logic snoop_done = 1'b0;
logic stall = 1'b0;
logic write_back = 1'b0;
logic hit = 1'b0, miss = 1'b0;
logic fill_pending = 1'b0;

MESI_STATES_t pending_state;
logic [1:0] pending_set;
logic       pending_way;
logic [1:0] pending_op;
logic [7:0] pending_addr;

logic [1:0] req_set;
logic [3:0] req_tag;
logic       way0_match,way1_match;
logic       req_hit;
logic       req_hit_way;

assign req_set     = c1_inf.inst[3:2];
assign req_tag      = c1_inf.inst[7:4];
assign way0_match   = c1_inf.cache_mem_out[req_set][0].valid && (c1_inf.cache_mem_out[req_set][0].tag == req_tag);
assign way1_match   = c1_inf.cache_mem_out[req_set][1].valid && (c1_inf.cache_mem_out[req_set][1].tag == req_tag);
assign req_hit      = way0_match || way1_match;
assign req_hit_way  = way1_match;


logic [1:0] snoop_set;
logic [3:0] snoop_tag;
logic       snoop_way0_match, snoop_way1_match;
logic       snoop_hit;
logic       snoop_hit_way;

assign snoop_set        = c1_inf.req_addr_in[3:2];
assign snoop_tag         = c1_inf.req_addr_in[7:4];
assign snoop_way0_match  = c1_inf.cache_mem_out[snoop_set][0].valid && (c1_inf.cache_mem_out[snoop_set][0].tag == snoop_tag);
assign snoop_way1_match  = c1_inf.cache_mem_out[snoop_set][1].valid && (c1_inf.cache_mem_out[snoop_set][1].tag == snoop_tag);
assign snoop_hit         = snoop_way0_match || snoop_way1_match;
assign snoop_hit_way     = snoop_way1_match;
l1_decision_t     dec;

always_ff @(posedge c1_inf.clk or posedge c1_inf.rst)
begin
  if (c1_inf.rst)
    C_PS <= IDLE;
  else
    C_PS <= C_NS;
end

always_comb
begin
  C_NS = C_PS;
  case(C_PS)
   IDLE : begin
            if(c1_inf.rst)
              begin
                C_NS <= IDLE;
              end
            else if(c1_inf.msg_req_in == MSG_FWD_GETS || c1_inf.msg_req_in == MSG_FWD_GETM || c1_inf.msg_req_in == MSG_INV)
              begin
                C_NS <= SNOOP;
              end
            else if (fill_pending == 1'b1)
              begin
                C_NS <= ALLOCATE;
              end
            else if (c1_inf.inst[9:8] == 2'b01 || c1_inf.inst[9:8] == 2'b10 || c1_inf.inst[9:8] == 2'b11)
               C_NS <= COMPARE;
            else
              begin
                C_NS <= IDLE;
              end
          end
   COMPARE : begin
               if(c1_inf.rst)
                 begin
                   C_NS <= IDLE;
                 end
                else if(fill_pending == 1'b1)
                 begin
                   C_NS <= ALLOCATE;
                 end
                else if (write_back)
                 begin
                   C_NS <= WRITEBACK;
                 end
                else if (done)
                 begin
                   C_NS <= DONE;
                 end
                else
                 begin
                   C_NS <= COMPARE;
                 end
             end
   ALLOCATE: begin
               if(c1_inf.rst)
                 begin
                   C_NS <= IDLE;
                 end
               else if (done)
                 begin
                   C_NS <= DONE;
                 end
               else
                 begin
                   C_NS <= ALLOCATE;
                 end
             end
    DONE : begin
            if(c1_inf.rst)
              C_NS <= IDLE;
            else if (c1_inf.msg_req_in == MSG_FWD_GETS || c1_inf.msg_req_in == MSG_FWD_GETM || c1_inf.msg_req_in == MSG_INV)
              C_NS <= SNOOP;
           else if(fill_pending == 1'b1 && c1_inf.msg_req_in == MSG_DATA)
              C_NS <= ALLOCATE;
           else if (fill_pending == 1'b1)
              C_NS <= DONE;
           else if (c1_inf.inst[9:8] == 2'b01 || c1_inf.inst[9:8] == 2'b10)
              C_NS <= COMPARE;
           else if (c1_inf.inst[9:8] == 2'b00)
              C_NS <= IDLE;
           else
              C_NS <= DONE;
          end
  SNOOP : begin
            if(c1_inf.rst)
              begin
                C_NS <= IDLE;
              end
            else if (fill_pending == 1'b1)
              begin
                C_NS <= ALLOCATE;
              end
            else if(done)
              begin
                C_NS <= DONE;
              end
          end
  WRITEBACK: begin
               if(c1_inf.rst)
                 begin
                   C_NS <= IDLE;
                 end
               else if(done)
                 begin
                   C_NS <= DONE;
                 end
               else
                 begin
                   C_NS <= WRITEBACK;
                 end
             end
   default : begin
               C_NS <= IDLE;
             end
  endcase
end
always_comb
begin
   cache_mem_out <= c1_inf.cache_mem_out;
end
always_ff @(posedge c1_inf.clk or posedge c1_inf.rst)
begin
  if (c1_inf.rst) begin
    hit           <= 1'b0;
    miss          <= 1'b0;
    stall         <= 1'b0;
    write_back    <= 1'b0;
    done          <= 1'b0;
    fill_pending  <= 1'b0;
    pending_state <= INVALID;
    pending_set   <= '0;
    pending_way   <= 1'b0;
    pending_op    <= '0;
    pending_addr  <= '0;
    c1_inf.msg_req_out  <= MSG_L1_NONE;
    c1_inf.req_addr_out <= '0;
    c1_inf.req_data_out <= '0;
    c1_inf.write_en     <= 1'b0;
    c1_inf.set_idx      <= '0;
    c1_inf.way_sel      <= 1'b0;
    c1_inf.update_line  <= '0;
    c1_inf.Data_out     <= '0;
    c1_inf.peer_id_out  <= '0;
  end else begin
 c1_inf.msg_req_out  <= MSG_L1_NONE;
c1_inf.req_addr_out <= '0;
c1_inf.req_data_out <= '0;
c1_inf.write_en     <= 1'b0;
  case(C_PS)
   IDLE : begin
            done <= 1'b0;
          end
   COMPARE : begin
               hit        <= 1'b0;
               miss       <= 1'b0;
               stall      <= 1'b0;
               write_back <= 1'b0;
              done       <= 1'b0;
              if(c1_inf.inst[9:8] == 2'b00 && !fill_pending)
                begin
                  done <= 1'b1;
                end
              else if (c1_inf.inst[9:8] == 2'b01 || c1_inf.inst[9:8] == 2'b10)
                begin
                if (req_hit) begin

                    dec = l1_decide(cache_mem_out[req_set][req_hit_way].C_tag, 1'b1, c1_inf.inst[9:8]);
                    $display(
                      "T=%0t inst=%h dec=%0d hit=%0b req_set=%0d req_tag=%0h req_hit_way = %d victim_state=%0d",
                       $time,
                       c1_inf.inst,
                        dec,
                        req_hit,
                       req_set,
                         req_tag,
                        req_hit_way,
                       cache_mem_out[req_set][req_hit_way].C_tag
                         );
                    case (dec.action)
                        ACTION_HIT: begin
                                     hit <= 1'b1;
                                     if (c1_inf.inst[9:8] == 2'b01) begin // load
                                       c1_inf.Data_out <= cache_mem_out[req_set][req_hit_way].data;
                                      end else begin // store
                                       c1_inf.write_en    <= 1'b1;
                                       c1_inf.set_idx      <= req_set;
                                       c1_inf.way_sel       <= req_hit_way;
                                       c1_inf.update_line  <= {1'b1, dec.next_state, req_tag, c1_inf.in_data};
                                      end
                                    done <= 1'b1;
                                   end
                        ACTION_UPGRADE: begin // S -> SM_D
                            c1_inf.msg_req_out  <= dec.msg_to_send; // GetM
                            c1_inf.req_addr_out <= c1_inf.inst[7:0];
                            pending_state        <= dec.next_state; // SM_D
                            pending_set          <= req_set;
                            pending_way          <= req_hit_way;
                            stall                <= 1'b1;
                            fill_pending         <= 1'b1;
                        end
                        ACTION_STALL_TRANSIENT: stall <= 1'b1;
                        default: ;
                    endcase
                end
                else begin
                    // Genuine miss
                    miss <= 1'b1;
                    if (!cache_mem_out[req_set][0].valid) begin
                        pending_way <= 1'b0;
                        dec = l1_decide(INVALID, 1'b0, c1_inf.inst[9:8]);
                        c1_inf.msg_req_out  <= dec.msg_to_send;
                        c1_inf.req_addr_out <= c1_inf.inst[7:0];
                        pending_state        <= dec.next_state;
                        pending_set          <= req_set;
                        pending_addr <= c1_inf.inst[7:0];
                        stall                <= 1'b1;
                        fill_pending         <= 1'b1;
                    end
                    else if (!cache_mem_out[req_set][1].valid) begin
                        pending_way <= 1'b1;
                        dec = l1_decide(INVALID, 1'b0, c1_inf.inst[9:8]);
                        c1_inf.msg_req_out  <= dec.msg_to_send;
                        c1_inf.req_addr_out <= c1_inf.inst[7:0];
                        pending_state        <= dec.next_state;
                        pending_set          <= req_set;
                        pending_addr <= c1_inf.inst[7:0];
                        stall                <= 1'b1;
                        fill_pending         <= 1'b1;
                    end
                    else begin
                        automatic logic         victim_way   = c1_inf.lru_way;
                        automatic MESI_STATES_t victim_state = cache_mem_out[req_set][victim_way].C_tag;

                        pending_set <= req_set;
                        pending_way <= victim_way;

                        if (victim_state == SHARED || victim_state == INVALID) begin
                            // silent evict, safe to fetch immediately
                            dec = l1_decide(INVALID, 1'b0, c1_inf.inst[9:8]);
                            c1_inf.msg_req_out  <= dec.msg_to_send;
                            c1_inf.req_addr_out <= c1_inf.inst[7:0];
                            pending_state        <= dec.next_state;
                            pending_addr <= c1_inf.inst[7:0];
                            stall                <= 1'b1;
                            fill_pending         <= 1'b1;
                        end
                        else begin
                            c1_inf.msg_req_out  <= (victim_state == MODIFIED) ? MSG_PUTM : MSG_PUTE;
                            c1_inf.req_addr_out <= {cache_mem_out[req_set][victim_way].tag, req_set, 2'b00};
                            if (victim_state == MODIFIED)
                              c1_inf.req_data_out <= cache_mem_out[req_set][victim_way].data;
                            pending_state <= (victim_state == MODIFIED) ? MI_A : EI_A;
                            pending_op    <= c1_inf.inst[9:8];
                            pending_addr  <= c1_inf.inst[7:0];
                            stall         <= 1'b1;
                            fill_pending  <= 1'b1;
                        end
                    end
                end
            end
           else if (c1_inf.inst[9:8] == 2'b11) begin
                if (req_hit) begin
                    dec = l1_decide(cache_mem_out[req_set][req_hit_way].C_tag, 1'b1, c1_inf.inst[9:8]);
                    case (dec.action)
                        ACTION_HIT: begin
                            c1_inf.write_en    <= 1'b1;
                            hit <= 1'b1;
                            c1_inf.set_idx      <= req_set;
                            c1_inf.way_sel       <= req_hit_way;
                            c1_inf.update_line  <= {1'b0, dec.next_state, 4'b0, 8'b0};
                            done <= 1'b1;
                        end
                        ACTION_STALL_TRANSIENT: begin
                            write_back            <= 1'b1;
                            c1_inf.msg_req_out    <= dec.msg_to_send;
                            c1_inf.req_addr_out   <= c1_inf.inst[7:0];
                            if(dec.msg_to_send == MSG_PUTM)
                              c1_inf.req_data_out <= cache_mem_out[req_set][req_hit_way].data;
                            pending_state          <= dec.next_state; // EI_A / MI_A
                            pending_set            <= req_set;
                            pending_way            <= req_hit_way;
                        end
                        default: ;
                    endcase
                end
                else begin
                    done <= 1'b1;
                end
            end
        end
 ALLOCATE : begin
             if (c1_inf.msg_req_in == MSG_DATA) begin
               case (pending_state)
                 EI_A, MI_A: begin

                c1_inf.write_en   <= 1'b1;
                c1_inf.set_idx     <= pending_set;
                c1_inf.way_sel      <= pending_way;
                c1_inf.update_line <= {1'b0, INVALID, 4'b0, 8'b0};

                c1_inf.msg_req_out  <= (pending_op == 2'b01) ? MSG_GETS : MSG_GETM;
                c1_inf.req_addr_out <= pending_addr;
                pending_state        <= (pending_op == 2'b01) ? IS_D : IM_D;

               end
                IS_D: begin
                c1_inf.write_en    <= 1'b1;
                c1_inf.set_idx      <= pending_set;
                c1_inf.way_sel       <= pending_way;
                c1_inf.Data_out     <= c1_inf.req_data_in;
                c1_inf.update_line  <= {1'b1,
                                          c1_inf.is_exclusive_in ? EXCLUSIVE : SHARED,
                                          pending_addr[7:4],
                                          c1_inf.req_data_in};
                c1_inf.msg_req_out  <= MSG_UNBLOCK;
                stall        <= 1'b0;
                fill_pending <= 1'b0;
                done         <= 1'b1;
               end
                IM_D: begin
                c1_inf.write_en    <= 1'b1;
                c1_inf.set_idx      <= pending_set;
                c1_inf.way_sel       <= pending_way;
                c1_inf.update_line  <= {1'b1, MODIFIED, pending_addr[7:4], c1_inf.req_data_in};
                c1_inf.msg_req_out  <= MSG_UNBLOCK;
                stall        <= 1'b0;
                fill_pending <= 1'b0;
                done         <= 1'b1;
              end
                SM_D: begin

                c1_inf.write_en    <= 1'b1;
                c1_inf.set_idx      <= pending_set;
                c1_inf.way_sel       <= pending_way;
                c1_inf.update_line  <= {1'b1, MODIFIED,
                                          c1_inf.cache_mem_out[pending_set][pending_way].tag,
                                          c1_inf.cache_mem_out[pending_set][pending_way].data};
                c1_inf.msg_req_out  <= MSG_UNBLOCK;
                stall        <= 1'b0;
                fill_pending <= 1'b0;
                done         <= 1'b1;
              end

            default: begin
             fill_pending <= 1'b0;
              stall        <= 1'b0;
               done         <= 1'b1;
              end
        endcase
    end
end
  DONE : begin
         done <= 1'b0;
         c1_inf.write_en <= 1'b0;
         hit <= 1'b0;
        miss <= 1'b0;
        if (!fill_pending) begin
        pending_state <= INVALID;
        pending_set   <= 'b0;
        pending_way   <= 'b0;
        pending_op    <= 'b0;
        pending_addr  <= 'b0;
    end
end
  SNOOP : begin
            if (!snoop_hit) begin
              done <= 1'b1;
             end
            else begin
             automatic MESI_STATES_t cur = c1_inf.cache_mem_out[snoop_set][snoop_hit_way].C_tag;
             automatic l1_decision_t sdec;
             unique case (cur)
              INVALID, SHARED, EXCLUSIVE, MODIFIED:
                sdec = l1_stable_net_decide(cur, c1_inf.msg_req_in);
              IS_D, IM_D, SM_D, EI_A, MI_A:
                sdec = l1_transient_decide(cur, c1_inf.msg_req_in);
              default: sdec = '0;
             endcase
             if (sdec.action == ACTION_FORWARD)
               c1_inf.peer_id_out <= c1_inf.peer_id_in;

            if (sdec.action != ACTION_STALL_TRANSIENT) begin
              c1_inf.msg_req_out <= sdec.msg_to_send;
            if (sdec.action == ACTION_FORWARD)
              c1_inf.peer_id_out <= c1_inf.peer_id_in;
            if (sdec.msg_to_send == MSG_DATAFWD || sdec.msg_to_send == MSG_PUTM)
               c1_inf.req_data_out <= c1_inf.cache_mem_out[snoop_set][snoop_hit_way].data;

              c1_inf.write_en <= 1'b1;
              c1_inf.set_idx   <= snoop_set;
              c1_inf.way_sel    <= snoop_hit_way;
            if (sdec.next_state == INVALID)
              c1_inf.update_line <= {1'b0, INVALID, 4'b0, 8'b0};
            else
             c1_inf.update_line <= {1'b1, sdec.next_state,
                                 c1_inf.cache_mem_out[snoop_set][snoop_hit_way].tag,
                                 c1_inf.cache_mem_out[snoop_set][snoop_hit_way].data};
            end
             done <= 1'b1;
           end
          end
  WRITEBACK : begin
                 if (c1_inf.msg_req_in == MSG_DATA) begin
                    c1_inf.write_en    <= 1'b1;
                    c1_inf.set_idx     <= pending_set;
                    c1_inf.way_sel     <= pending_way;
                    c1_inf.update_line <= {1'b0, INVALID, 4'b0, 8'b0};
                     write_back <= 1'b0;
                    done       <= 1'b1;
                  end
               end
  endcase
  end
end
always_comb
begin
  c1_inf.lru_id = '0;
  c1_inf.update_lru = 1'b0;
  if (hit || miss)
   begin
     if(c1_inf.msg_req_in == MSG_FWD_GETM || c1_inf.msg_req_in == MSG_FWD_GETS)
       begin
         c1_inf.lru_id = c1_inf.req_addr_in[3:2];
         c1_inf.update_lru = 1'b1;
       end
     else if (c1_inf.inst[9:8] == 2'b01 || c1_inf.inst[9:8] == 2'b10)
        begin
          c1_inf.lru_id = c1_inf.inst[3:2];
          c1_inf.update_lru = 1'b1;
        end
   end
  else
    c1_inf.update_lru = 1'b0;
end
function l1_decision_t l1_decide(
    input MESI_STATES_t cur_state,
    input logic         line_valid,
    input logic [1:0]   inst
);
    logic is_load;
    logic flush;
    l1_decide = '0;

    is_load = (inst == 2'b01);
    flush = (inst == 2'b11);
    if(flush)
      begin
        case(cur_state)
         EXCLUSIVE : begin
                       l1_decide.action = ACTION_STALL_TRANSIENT;
                       l1_decide.msg_to_send = MSG_PUTE;
                       l1_decide.next_state = EI_A;
                     end
          MODIFIED : begin
                       l1_decide.action = ACTION_STALL_TRANSIENT;
                       l1_decide.msg_to_send = MSG_PUTM;
                       l1_decide.next_state = MI_A;
                     end
         SHARED : begin
                     l1_decide.action = ACTION_HIT;
                     l1_decide.next_state = INVALID;
                  end
        endcase
      end

    else if (!line_valid) begin
        l1_decide.action      = ACTION_MISS;
        l1_decide.msg_to_send = is_load ? MSG_GETS : MSG_GETM;
        l1_decide.next_state  = is_load ? IS_D : IM_D;
    end
    else
       begin
        case (cur_state)
        MODIFIED, EXCLUSIVE: begin
            l1_decide.action     = ACTION_HIT;
            l1_decide.next_state = is_load ? cur_state : MODIFIED;
        end
        SHARED: begin
            if (is_load) begin
                l1_decide.action     = ACTION_HIT;
                l1_decide.next_state = SHARED;
            end else begin
                l1_decide.action      = ACTION_UPGRADE;
                l1_decide.msg_to_send = MSG_GETM;
                l1_decide.next_state  = SM_D;
            end
        end
        INVALID : begin
                    if(is_load)
                      begin
                        l1_decide.action = ACTION_MISS;
                        l1_decide.msg_to_send = MSG_GETS;
                        l1_decide.next_state = IS_D;
                      end
                    else
                      begin
                         l1_decide.action = ACTION_MISS;
                        l1_decide.msg_to_send = MSG_GETM;
                        l1_decide.next_state = IM_D;
                      end
                  end
        IS_D, IM_D, SM_D, EI_A, MI_A: l1_decide.action = ACTION_STALL_TRANSIENT;
        default: l1_decide.action = ACTION_STALL_TRANSIENT;
    endcase
       end
endfunction

function l1_decision_t l1_decide_on_msg(
    input MESI_STATES_t cur_state,
    input l1_msg_in_t   msg_req_in
);
    l1_decide_on_msg = '0;

    case (cur_state)

        IS_D: case (msg_req_in)
            MSG_DATA: begin
                l1_decide_on_msg.action      = ACTION_HIT;
                l1_decide_on_msg.msg_to_send = MSG_UNBLOCK;
                l1_decide_on_msg.next_state  = SHARED;
            end
            default: l1_decide_on_msg.action = ACTION_STALL_TRANSIENT;
        endcase

        IM_D: case (msg_req_in)
            MSG_DATA: begin
                l1_decide_on_msg.action      = ACTION_HIT;
                l1_decide_on_msg.msg_to_send = MSG_UNBLOCK;
                l1_decide_on_msg.next_state  = MODIFIED;
            end
            default: l1_decide_on_msg.action = ACTION_STALL_TRANSIENT;
        endcase

        SM_D: case (msg_req_in)
            MSG_DATA: begin
                l1_decide_on_msg.action      = ACTION_HIT;
                l1_decide_on_msg.msg_to_send = MSG_UNBLOCK;
                l1_decide_on_msg.next_state  = MODIFIED;
            end
            default: l1_decide_on_msg.action = ACTION_STALL_TRANSIENT;
        endcase

        EI_A, MI_A: case (msg_req_in)
            MSG_DATA: begin  // empty Data message used as Put-Ack
                l1_decide_on_msg.action      = ACTION_HIT;
                l1_decide_on_msg.msg_to_send = MSG_UNBLOCK;
                l1_decide_on_msg.next_state  = INVALID;
            end
            default: l1_decide_on_msg.action = ACTION_STALL_TRANSIENT;
        endcase

        default: l1_decide_on_msg.action = ACTION_STALL_TRANSIENT;

    endcase
endfunction

function l1_decision_t l1_stable_net_decide(  // for snoop
    input MESI_STATES_t cur_state,
    input  l1_msg_in_t msg_req_in
);
    l1_stable_net_decide = '0;

    case (cur_state)

        INVALID: case (msg_req_in)
            MSG_INV: begin
                l1_stable_net_decide.action      = ACTION_ACK_VACUOUS;
                l1_stable_net_decide.msg_to_send = MSG_INVACK;
                l1_stable_net_decide.next_state  = INVALID;
            end
            default: l1_stable_net_decide.action = ACTION_STALL_TRANSIENT;
        endcase

        SHARED: case (msg_req_in)
            MSG_INV: begin
                l1_stable_net_decide.action      = ACTION_INVALIDATE;
                l1_stable_net_decide.msg_to_send = MSG_INVACK;
                l1_stable_net_decide.next_state  = INVALID;
            end
            default: l1_stable_net_decide.action = ACTION_STALL_TRANSIENT;
        endcase

        EXCLUSIVE: case (msg_req_in)
             MSG_INV: begin
               l1_stable_net_decide.action      = ACTION_INVALIDATE;
               l1_stable_net_decide.msg_to_send = MSG_PUTE;
               l1_stable_net_decide.next_state  = INVALID;
              end
            MSG_FWD_GETS: begin
                l1_stable_net_decide.action      = ACTION_FORWARD;
                l1_stable_net_decide.msg_to_send = MSG_DATAFWD;
                l1_stable_net_decide.msg_to_dir  = MSG_ACK;
                l1_stable_net_decide.next_state  = SHARED;
            end
            MSG_FWD_GETM: begin
                l1_stable_net_decide.action      = ACTION_FORWARD;
                l1_stable_net_decide.msg_to_send = MSG_DATAFWD;
                l1_stable_net_decide.msg_to_dir  = MSG_ACK;
                l1_stable_net_decide.next_state  = INVALID;
            end
            default: l1_stable_net_decide.action = ACTION_STALL_TRANSIENT;
        endcase

        MODIFIED: case (msg_req_in)
            MSG_INV: begin
              l1_stable_net_decide.action      = ACTION_INVALIDATE;
              l1_stable_net_decide.msg_to_send = MSG_PUTM;
              l1_stable_net_decide.next_state  = INVALID;
            end
            MSG_FWD_GETS: begin
                l1_stable_net_decide.action      = ACTION_FORWARD;
                l1_stable_net_decide.msg_to_send = MSG_DATAFWD;
                l1_stable_net_decide.msg_to_dir  = MSG_ACK;
                l1_stable_net_decide.next_state  = SHARED;
            end
            MSG_FWD_GETM: begin
                l1_stable_net_decide.action      = ACTION_FORWARD;
                l1_stable_net_decide.msg_to_send = MSG_DATAFWD;
                l1_stable_net_decide.msg_to_dir  = MSG_ACK;
                l1_stable_net_decide.next_state  = INVALID;
            end
            default: l1_stable_net_decide.action = ACTION_STALL_TRANSIENT;
        endcase

        default: l1_stable_net_decide.action = ACTION_STALL_TRANSIENT;

    endcase
endfunction

function l1_decision_t l1_transient_decide(  //for snoop
    input MESI_STATES_t cur_state,
    input l1_msg_in_t   msg_req_in
);
    l1_transient_decide = '0;

    case (cur_state)
        IS_D, IM_D: begin
            l1_transient_decide.action     = ACTION_STALL_TRANSIENT;
            l1_transient_decide.next_state = cur_state;
        end

        SM_D: case (msg_req_in)
            MSG_INV: begin
                l1_transient_decide.action      = ACTION_INVALIDATE;
                l1_transient_decide.msg_to_send = MSG_INVACK;
                l1_transient_decide.next_state  = IM_D;
            end
            default: begin
                l1_transient_decide.action     = ACTION_STALL_TRANSIENT;
                l1_transient_decide.next_state = SM_D;
            end
        endcase

        MI_A, EI_A: case (msg_req_in)
            MSG_FWD_GETS: begin
                l1_transient_decide.action      = ACTION_FORWARD;
                l1_transient_decide.msg_to_send = MSG_DATAFWD;
                l1_transient_decide.next_state  = SHARED;
            end
            MSG_FWD_GETM: begin
                l1_transient_decide.action      = ACTION_FORWARD;
                l1_transient_decide.msg_to_send = MSG_DATAFWD;
                l1_transient_decide.next_state  = INVALID;
            end
            default: begin
                l1_transient_decide.action     = ACTION_STALL_TRANSIENT;
                l1_transient_decide.next_state = cur_state;
            end
        endcase

        default: l1_transient_decide.action = ACTION_STALL_TRANSIENT;
    endcase
endfunction

endmodule
