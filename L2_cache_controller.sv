import l2_cache_pkg::*;
import L1_cache_mem::*;

module l2_cache_controller #(
    parameter logic [1:0] MY_BANK_ID = 2'd0   // this core's own id
) (
    L2_cache.L2_cache_controller_mb c2_inf
);
    localparam logic [2:0] MEM_ID = 3'd4;

    L2_STATES_t C_PS, C_NS;

    logic done         = 1'b0;
    logic fill_pending = 1'b0;

    dir_state_t pending_state;
    logic [1:0] pending_set, pending_way;
    logic [1:0] pending_owner;
    logic [3:0] pending_send;
    logic [3:0] pending_ack;

    typedef enum logic [1:0] {OP_GETS, OP_GETM, OP_PUTM, OP_PUTE} op_t;
    op_t        req_op;
    logic       req_from_nic;
    logic [1:0] req_src;
    logic [7:0] req_addr;
    logic [7:0] req_data;

    l2_nic_msg_t pending_snoop_msg;
    logic        snoop_sent;


    logic        mem_req_sent;
    logic [7:0]  evict_wb_data;
    logic        evict_wb_we;

    logic [1:0] req_set;
    logic [3:0] req_tag;
    assign req_set = req_addr[7:6];
    assign req_tag = req_addr[3:0];

    logic [3:0] way_match;
    logic compare_settled;
    always_ff @(posedge c2_inf.clk or posedge c2_inf.rst) begin
       if (c2_inf.rst) compare_settled <= 1'b0;
         else begin
           compare_settled <= (C_PS == L2_COMPARE);
          end
        end
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi++) begin : g_match
            assign way_match[gi] = (c2_inf.cache_mem_out[req_set][gi].valid === 1'b1) &&
                                    (c2_inf.cache_mem_out[req_set][gi].tag == req_tag);
        end
    endgenerate

    logic [1:0] fifo_ptr [0:3];


    logic l1_is_dir_req;
    assign l1_is_dir_req = (c2_inf.l1_msg_req_in == MSG_GETS) || (c2_inf.l1_msg_req_in == MSG_GETM) ||
                            (c2_inf.l1_msg_req_in == MSG_PUTM) || (c2_inf.l1_msg_req_in == MSG_PUTE);

    logic nic_is_dir_req, nic_is_snoop_req;
    assign nic_is_dir_req   = (c2_inf.req_nic_pkt_i.msg == NMSG_GETS) || (c2_inf.req_nic_pkt_i.msg == NMSG_GETM) ||
                              (c2_inf.req_nic_pkt_i.msg == NMSG_PUTM) || (c2_inf.req_nic_pkt_i.msg == NMSG_PUTE);
    assign nic_is_snoop_req = (c2_inf.req_nic_pkt_i.msg == NMSG_FWD_GETS) ||
                              (c2_inf.req_nic_pkt_i.msg == NMSG_FWD_GETM) ||
                              (c2_inf.req_nic_pkt_i.msg == NMSG_INV);

    function l2_decision_t l2_dir_hit_decide(
        input dir_state_t  cur_state,
        input logic        is_owner,
        input l1_msg_out_t msg
    );
        l2_dir_hit_decide = '0;
        case (cur_state)
            DIR_S: begin
                if (msg == MSG_GETS) begin
                    l2_dir_hit_decide.action     = L2_ACTION_HIT;
                    l2_dir_hit_decide.next_state = DIR_S;
                end
                else begin
                    l2_dir_hit_decide.action     = L2_ACTION_UPGRADE_INV;
                    l2_dir_hit_decide.next_state = DIR_INV_WAIT;
                end
            end
            DIR_E, DIR_M: begin
                if (is_owner) begin
                    l2_dir_hit_decide.action     = L2_ACTION_HIT;
                    l2_dir_hit_decide.next_state = cur_state;
                end
                else begin
                    l2_dir_hit_decide.action      = L2_ACTION_FORWARD;
                    l2_dir_hit_decide.msg_to_send = (msg == MSG_GETS) ? MSG_FWD_GETS : MSG_FWD_GETM;
                    l2_dir_hit_decide.next_state  = DIR_FWD_WAIT;
                end
            end
            default: l2_dir_hit_decide.action = L2_ACTION_NONE;
        endcase
    endfunction

    function l2_decision_t l2_evict_decide(
        input logic       victim_valid,
        input dir_state_t victim_state,
        input logic [1:0] victim_owner
    );
        l2_evict_decide = '0;
        if (victim_valid !== 1'b1) begin
            l2_evict_decide.action     = L2_ACTION_MISS;
            l2_evict_decide.next_state = DIR_MEM_WAIT;
        end
        else if (victim_state == DIR_S) begin
            l2_evict_decide.action     = L2_ACTION_EVICT_INV;
            l2_evict_decide.next_state = DIR_EVICT_INV_WAIT;
        end
        else begin // DIR_E or DIR_M
            l2_evict_decide.action      = L2_ACTION_EVICT_RECALL;
            l2_evict_decide.msg_to_send = MSG_INV;
            l2_evict_decide.next_state  = DIR_EVICT_FWD_WAIT;
            l2_evict_decide.target_id   = victim_owner;
        end
    endfunction

    always_ff @(posedge c2_inf.clk or posedge c2_inf.rst)
    begin
        if (c2_inf.rst)
            C_PS <= L2_IDLE;
        else
            C_PS <= C_NS;
    end

    logic compare_will_wait, compare_will_finish;
    logic [1:0] compare_hit_way, compare_requester;
    l2_decision_t compare_decision;
    always_comb begin
        compare_will_wait   = 1'b0;
        compare_will_finish = 1'b0;
        compare_hit_way     = '0;
        compare_requester   = '0;
        compare_decision    = '0;
        if (C_PS == L2_COMPARE && compare_settled) begin
            if (req_op == OP_GETS || req_op == OP_GETM) begin
                if (|way_match) begin
                    compare_hit_way = way_match[0] ? 2'd0 : way_match[1] ? 2'd1 : way_match[2] ? 2'd2 : 2'd3;
                    compare_requester = req_from_nic ? req_src : MY_BANK_ID;
                    compare_decision = l2_dir_hit_decide(c2_inf.cache_mem_out[req_set][compare_hit_way].C_tag,
                                                         c2_inf.cache_mem_out[req_set][compare_hit_way].owner_id == compare_requester,
                                                         (req_op == OP_GETS) ? MSG_GETS : MSG_GETM);
                    compare_will_wait   = (compare_decision.action == L2_ACTION_UPGRADE_INV) || (compare_decision.action == L2_ACTION_FORWARD);
                    compare_will_finish = (compare_decision.action == L2_ACTION_HIT);
                end
                else begin
                    compare_will_wait = 1'b1;
                end
            end
            else begin
                compare_will_finish = 1'b1;
            end
        end
    end

    logic allocate_will_finish;
    always_comb begin
        allocate_will_finish = 1'b0;
        if (C_PS == L2_ALLOCATE) begin
            case (pending_state)
                DIR_MEM_WAIT: allocate_will_finish = mem_req_sent && c2_inf.req_valid_i &&
                                                       (c2_inf.req_nic_pkt_i.msg == NMSG_MEM_DATA) &&
                                                       (c2_inf.req_nic_pkt_i.src_id == MEM_ID);
                DIR_FWD_WAIT: begin
                    if (pending_owner == MY_BANK_ID)
                        allocate_will_finish = (c2_inf.l1_msg_req_in == MSG_DATAFWD);
                    else
                        allocate_will_finish = c2_inf.req_valid_i && (c2_inf.req_nic_pkt_i.msg == NMSG_DATAFWD) &&
                                                 (c2_inf.req_nic_pkt_i.src_id[1:0] == pending_owner);
                end
                DIR_INV_WAIT: begin
                    automatic logic [3:0] next_ack;
                    next_ack = pending_ack;
                    if (c2_inf.l1_msg_req_in == MSG_INVACK) next_ack[MY_BANK_ID] = 1'b0;
                    if (c2_inf.req_valid_i && c2_inf.req_nic_pkt_i.msg == NMSG_INVACK)
                        next_ack[c2_inf.req_nic_pkt_i.src_id[1:0]] = 1'b0;
                    allocate_will_finish = (next_ack == '0);
                end
                default: allocate_will_finish = 1'b0;
            endcase
        end
    end

    logic snoop_will_finish;
    always_comb begin
        snoop_will_finish = 1'b0;
        if (C_PS == L2_SNOOP && snoop_sent) begin
            snoop_will_finish = (c2_inf.l1_msg_req_in == MSG_DATAFWD) || (c2_inf.l1_msg_req_in == MSG_PUTM) ||
                                 (c2_inf.l1_msg_req_in == MSG_PUTE)   || (c2_inf.l1_msg_req_in == MSG_INVACK);
        end
    end

    always_comb
    begin
        case (C_PS)
            L2_IDLE : begin
                        if (c2_inf.rst)
                          C_NS = L2_IDLE;
                        else if (fill_pending)
                          C_NS = L2_ALLOCATE;
                        else if (l1_is_dir_req)
                          C_NS = L2_COMPARE;
                        else if (c2_inf.req_valid_i && nic_is_snoop_req)
                          C_NS = L2_SNOOP;
                        else if (c2_inf.req_valid_i && nic_is_dir_req)
                          C_NS = L2_COMPARE;
                        else
                          C_NS = L2_IDLE;
                      end
            L2_COMPARE : begin
                        if (c2_inf.rst)
                          C_NS = L2_IDLE;
                        else if (compare_will_wait)
                          C_NS = L2_ALLOCATE;
                        else if (compare_will_finish)
                          C_NS = L2_DONE;
                        else
                          C_NS = L2_COMPARE;
                      end
            L2_ALLOCATE : begin
                        if (c2_inf.rst)
                          C_NS = L2_IDLE;
                        else if (allocate_will_finish)
                          C_NS = L2_DONE;
                        else
                          C_NS = L2_ALLOCATE;
                      end
            L2_SNOOP : begin
                        if (c2_inf.rst)
                          C_NS = L2_IDLE;
                        else if (snoop_will_finish)
                          C_NS = L2_DONE;
                        else
                          C_NS = L2_SNOOP;
                      end
            L2_DONE : begin
                        C_NS = c2_inf.rst ? L2_IDLE : L2_IDLE;
                      end
            default : C_NS = L2_IDLE;
        endcase
    end

    always_ff @(posedge c2_inf.clk or posedge c2_inf.rst)
    begin
        if (c2_inf.rst) begin
            done          <= 1'b0;
            fill_pending  <= 1'b0;
            pending_state <= DIR_I;
            pending_set   <= '0;
            pending_way   <= '0;
            pending_owner <= '0;
            pending_send  <= '0;
            pending_ack   <= '0;
            req_op        <= OP_GETS;
            req_from_nic  <= 1'b0;
            req_src       <= '0;
            req_addr      <= '0;
            req_data      <= '0;
            pending_snoop_msg <= NMSG_NONE;
            snoop_sent    <= 1'b0;
            mem_req_sent  <= 1'b0;
            evict_wb_data <= '0;
            evict_wb_we   <= 1'b0;
            for (int s = 0; s < 4; s++) fifo_ptr[s] <= 2'd0;
            c2_inf.write_en     <= 1'b0;
            c2_inf.set_idx      <= '0;
            c2_inf.way_sel      <= '0;
            c2_inf.update_line  <= '0;
            c2_inf.l2_l1_data_o <= '{msg_in: MSG_NONE, is_exclusive_in: 1'b0, addr: '0, data: '0, requester_id: '0};
            c2_inf.req_ready_o  <= 1'b0;
            c2_inf.resp_valid_o <= 1'b0;
            c2_inf.resp_nic_data_o <= '0;
        end else begin
        c2_inf.write_en     <= 1'b0;
        c2_inf.req_ready_o  <= 1'b0;
        c2_inf.resp_valid_o <= 1'b0;
        c2_inf.l2_l1_data_o <= '{msg_in: MSG_NONE, is_exclusive_in: 1'b0, addr: '0, data: '0, requester_id: '0};

        case (C_PS)

        L2_IDLE : begin
                    done <= 1'b0;
                    if (l1_is_dir_req) begin
                        req_from_nic <= 1'b0;
                        req_addr     <= c2_inf.req_addr_out;
                        req_data     <= c2_inf.req_data_out;
                        req_op       <= (c2_inf.l1_msg_req_in == MSG_GETS) ? OP_GETS :
                                        (c2_inf.l1_msg_req_in == MSG_GETM) ? OP_GETM :
                                        (c2_inf.l1_msg_req_in == MSG_PUTM) ? OP_PUTM : OP_PUTE;
                    end
                    else if (c2_inf.req_valid_i && nic_is_snoop_req) begin
                        c2_inf.req_ready_o <= 1'b1;
                        req_from_nic       <= 1'b1;
                        req_src            <= c2_inf.req_nic_pkt_i.src_id[1:0];
                        req_addr           <= c2_inf.req_nic_pkt_i.addr;
                        req_data           <= c2_inf.req_nic_pkt_i.data;
                        pending_snoop_msg  <= c2_inf.req_nic_pkt_i.msg;
                        snoop_sent         <= 1'b0;
                    end
                    else if (c2_inf.req_valid_i && nic_is_dir_req) begin
                        c2_inf.req_ready_o <= 1'b1;
                        req_from_nic       <= 1'b1;
                        req_src            <= c2_inf.req_nic_pkt_i.src_id[1:0];
                        req_addr           <= c2_inf.req_nic_pkt_i.addr;
                        req_data           <= c2_inf.req_nic_pkt_i.data;
                        req_op             <= (c2_inf.req_nic_pkt_i.msg == NMSG_GETS) ? OP_GETS :
                                              (c2_inf.req_nic_pkt_i.msg == NMSG_GETM) ? OP_GETM :
                                              (c2_inf.req_nic_pkt_i.msg == NMSG_PUTM) ? OP_PUTM : OP_PUTE;
                    end
                  end

        L2_COMPARE : begin
                    done         <= 1'b0;
                    fill_pending <= 1'b0;

                    if (compare_settled) begin
                    if (req_op == OP_GETS || req_op == OP_GETM) begin
                        if (|way_match) begin
                            automatic logic [1:0] hit_way;
                            automatic logic [1:0] requester;
                            automatic l2_decision_t dec;
                            hit_way   = way_match[0] ? 2'd0 : way_match[1] ? 2'd1 :
                                        way_match[2] ? 2'd2 : 2'd3;
                            requester = req_from_nic ? req_src : MY_BANK_ID;
                            dec = l2_dir_hit_decide(c2_inf.cache_mem_out[req_set][hit_way].C_tag,
                                                     c2_inf.cache_mem_out[req_set][hit_way].owner_id == requester,
                                                     (req_op == OP_GETS) ? MSG_GETS : MSG_GETM);
                            pending_set <= req_set;
                            pending_way <= hit_way;

                            case (dec.action)
                                L2_ACTION_HIT: begin
                                    automatic logic is_excl;
                                    is_excl = (req_op == OP_GETM) ||
                                              (c2_inf.cache_mem_out[req_set][hit_way].sharers == '0);
                                    if (req_op == OP_GETS) begin
                                        c2_inf.write_en    <= 1'b1;
                                        c2_inf.set_idx     <= req_set;
                                        c2_inf.way_sel     <= hit_way;
                                        c2_inf.update_line <= {1'b1, c2_inf.cache_mem_out[req_set][hit_way].C_tag,
                                            req_tag,
                                            c2_inf.cache_mem_out[req_set][hit_way].sharers | (4'd1 << requester),
                                            c2_inf.cache_mem_out[req_set][hit_way].owner_id,
                                            c2_inf.cache_mem_out[req_set][hit_way].data};
                                    end
                                    if (req_from_nic) begin
                                        c2_inf.resp_valid_o    <= 1'b1;
                                        c2_inf.resp_nic_data_o <= '{msg: NMSG_DATA, we: 1'b0, is_exclusive_in: is_excl,
                                            addr: req_addr, data: c2_inf.cache_mem_out[req_set][hit_way].data,
                                            src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, req_src}};
                                    end else begin
                                        c2_inf.l2_l1_data_o <= '{msg_in: MSG_DATA, is_exclusive_in: is_excl,
                                            addr: req_addr, data: c2_inf.cache_mem_out[req_set][hit_way].data, requester_id: '0};
                                    end
                                    done <= 1'b1;
                                end

                                L2_ACTION_UPGRADE_INV: begin
                                    automatic logic [3:0] targets;
                                    targets = c2_inf.cache_mem_out[req_set][hit_way].sharers & ~(4'd1 << requester);
                                    pending_send <= targets;
                                    pending_ack  <= targets;
                                    c2_inf.write_en    <= 1'b1;
                                    c2_inf.set_idx     <= req_set;
                                    c2_inf.way_sel     <= hit_way;
                                    c2_inf.update_line <= {1'b1, DIR_INV_WAIT, req_tag,
                                        c2_inf.cache_mem_out[req_set][hit_way].sharers,
                                        c2_inf.cache_mem_out[req_set][hit_way].owner_id,
                                        c2_inf.cache_mem_out[req_set][hit_way].data};
                                    pending_state <= DIR_INV_WAIT;
                                    fill_pending  <= 1'b1;
                                end

                                L2_ACTION_FORWARD: begin
                                    automatic logic [1:0] owner;
                                    automatic logic [1:0] requester;
                                    owner     = c2_inf.cache_mem_out[req_set][hit_way].owner_id;
                                    requester = req_from_nic ? req_src : MY_BANK_ID;
                                    pending_owner <= owner;
                                    if (owner == MY_BANK_ID) begin
                                        c2_inf.l2_l1_data_o <= '{msg_in: dec.msg_to_send, is_exclusive_in: 1'b0,
                                            addr: req_addr, data: 8'b0, requester_id: requester};
                                    end else begin
                                        c2_inf.resp_valid_o    <= 1'b1;
                                        c2_inf.resp_nic_data_o <= '{
                                            msg: (dec.msg_to_send == MSG_FWD_GETS) ? NMSG_FWD_GETS : NMSG_FWD_GETM,
                                            we: 1'b0, is_exclusive_in: 1'b0, addr: req_addr, data: 8'b0,
                                            src_id: {1'b0, requester}, dest_id: {1'b0, owner}};
                                    end
                                    c2_inf.write_en    <= 1'b1;
                                    c2_inf.set_idx     <= req_set;
                                    c2_inf.way_sel     <= hit_way;
                                    c2_inf.update_line <= {1'b1, DIR_FWD_WAIT, req_tag,
                                        c2_inf.cache_mem_out[req_set][hit_way].sharers, owner,
                                        c2_inf.cache_mem_out[req_set][hit_way].data};
                                    pending_state <= DIR_FWD_WAIT;
                                    fill_pending  <= 1'b1;
                                end

                                default: ;
                            endcase
                        end
                        else begin
                            automatic logic [1:0]    v;
                            automatic l2_decision_t  edec;
                            v = fifo_ptr[req_set];
                            edec = l2_evict_decide(c2_inf.cache_mem_out[req_set][v].valid,
                                                    c2_inf.cache_mem_out[req_set][v].C_tag,
                                                    c2_inf.cache_mem_out[req_set][v].owner_id);
                            pending_set       <= req_set;
                            pending_way       <= v;
                            fifo_ptr[req_set] <= fifo_ptr[req_set] + 2'd1;
                            fill_pending      <= 1'b1;
                            pending_state     <= edec.next_state;

                            case (edec.action)
                                L2_ACTION_MISS: begin
                                    c2_inf.write_en     <= 1'b1;
                                    c2_inf.set_idx      <= req_set;
                                    c2_inf.way_sel      <= v;
                                    c2_inf.update_line  <= {1'b1, DIR_MEM_WAIT, req_tag, 4'b0, 2'b0, 8'b0};
                                end
                                L2_ACTION_EVICT_INV: begin
                                    pending_send <= c2_inf.cache_mem_out[req_set][v].sharers;
                                    pending_ack  <= c2_inf.cache_mem_out[req_set][v].sharers;
                                end
                                L2_ACTION_EVICT_RECALL: begin
                                    automatic logic [7:0] victim_addr;
                                    victim_addr = {req_set, MY_BANK_ID, c2_inf.cache_mem_out[req_set][v].tag};
                                    pending_owner <= edec.target_id;
                                    if (edec.target_id == MY_BANK_ID) begin
                                        c2_inf.l2_l1_data_o <= '{msg_in: MSG_INV, is_exclusive_in: 1'b0,
                                            addr: victim_addr, data: 8'b0, requester_id: '0};
                                    end else begin
                                        c2_inf.resp_valid_o    <= 1'b1;
                                        c2_inf.resp_nic_data_o <= '{msg: NMSG_INV, we: 1'b0, is_exclusive_in: 1'b0,
                                            addr: victim_addr, data: 8'b0,
                                            src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, edec.target_id}};
                                    end
                                end
                                default: ;
                            endcase
                        end
                    end
                    else begin
                        automatic logic [1:0] requester;
                        requester = req_from_nic ? req_src : MY_BANK_ID;
                        if (|way_match) begin
                            automatic logic [1:0] hit_way;
                            hit_way = way_match[0] ? 2'd0 : way_match[1] ? 2'd1 :
                                      way_match[2] ? 2'd2 : 2'd3;
                            if (c2_inf.cache_mem_out[req_set][hit_way].owner_id == requester) begin
                                c2_inf.write_en    <= 1'b1;
                                c2_inf.set_idx     <= req_set;
                                c2_inf.way_sel     <= hit_way;
                                c2_inf.update_line <= {1'b1, DIR_I, req_tag, 4'b0, 2'b0,
                                    (req_op == OP_PUTM) ? req_data : c2_inf.cache_mem_out[req_set][hit_way].data};
                            end
                        end
                        if (req_from_nic) begin
                            c2_inf.resp_valid_o    <= 1'b1;
                            c2_inf.resp_nic_data_o <= '{msg: NMSG_DATA, we: 1'b0, is_exclusive_in: 1'b0,
                                addr: req_addr, data: 8'b0, src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, req_src}};
                        end else begin
                            c2_inf.l2_l1_data_o <= '{msg_in: MSG_DATA, is_exclusive_in: 1'b0,
                                addr: req_addr, data: 8'b0, requester_id: '0};
                        end
                        done <= 1'b1;
                    end
                    end
                  end

        L2_ALLOCATE : begin
                    case (pending_state)

                    DIR_MEM_WAIT: begin
                        if (!mem_req_sent) begin
                            c2_inf.resp_valid_o    <= 1'b1;
                            c2_inf.resp_nic_data_o <= '{msg: NMSG_MEM_REQ, we: 1'b0, is_exclusive_in: 1'b0,
                                addr: req_addr, data: 8'b0,
                                src_id: {1'b0, MY_BANK_ID}, dest_id: MEM_ID};
                            mem_req_sent <= 1'b1;
                        end
                        else if (c2_inf.req_valid_i && c2_inf.req_nic_pkt_i.msg == NMSG_MEM_DATA &&
                                 c2_inf.req_nic_pkt_i.src_id == MEM_ID) begin
                            automatic logic [1:0] requester;
                            c2_inf.req_ready_o <= 1'b1;
                            requester = req_from_nic ? req_src : MY_BANK_ID;
                            c2_inf.write_en    <= 1'b1;
                            c2_inf.set_idx     <= pending_set;
                            c2_inf.way_sel     <= pending_way;
                            c2_inf.update_line <= {1'b1, (req_op == OP_GETS) ? DIR_E : DIR_M, req_tag,
                                (4'd1 << requester), requester, c2_inf.req_nic_pkt_i.data};
                            if (req_from_nic) begin
                                c2_inf.resp_valid_o    <= 1'b1;
                                c2_inf.resp_nic_data_o <= '{msg: NMSG_DATA, we: 1'b0, is_exclusive_in: 1'b1,
                                    addr: req_addr, data: c2_inf.req_nic_pkt_i.data,
                                    src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, req_src}};
                            end else begin
                                c2_inf.l2_l1_data_o <= '{msg_in: MSG_DATA, is_exclusive_in: 1'b1,
                                    addr: req_addr, data: c2_inf.req_nic_pkt_i.data, requester_id: '0};
                            end
                            fill_pending <= 1'b0;
                            done         <= 1'b1;
                            mem_req_sent <= 1'b0;
                        end
                    end

                    DIR_FWD_WAIT: begin
                        automatic logic       dataf_seen;
                        automatic logic [7:0] fwd_data;
                        if (pending_owner == MY_BANK_ID) begin
                            dataf_seen = (c2_inf.l1_msg_req_in == MSG_DATAFWD);
                            fwd_data   = c2_inf.req_data_out;
                        end else begin
                            dataf_seen = c2_inf.req_valid_i && (c2_inf.req_nic_pkt_i.msg == NMSG_DATAFWD) &&
                                         (c2_inf.req_nic_pkt_i.src_id[1:0] == pending_owner);
                            fwd_data   = c2_inf.req_nic_pkt_i.data;
                        end
                        if (!dataf_seen && pending_owner == MY_BANK_ID) begin
                            c2_inf.l2_l1_data_o <= '{
                                msg_in: (req_op == OP_GETS) ? MSG_FWD_GETS : MSG_FWD_GETM,
                                is_exclusive_in: 1'b0, addr: req_addr, data: 8'b0,
                                requester_id: (req_from_nic ? req_src : MY_BANK_ID)};
                        end
                        if (dataf_seen) begin
                            automatic logic [1:0]  requester;
                            automatic dir_state_t   nstate;
                            automatic logic [3:0]   nsharers;
                            requester = req_from_nic ? req_src : MY_BANK_ID;
                            nstate    = (req_op == OP_GETS) ? DIR_S : DIR_M;
                            nsharers  = (req_op == OP_GETS) ? ((4'd1 << pending_owner) | (4'd1 << requester))
                                                             : (4'd1 << requester);
                            if (pending_owner != MY_BANK_ID) c2_inf.req_ready_o <= 1'b1;
                            c2_inf.write_en    <= 1'b1;
                            c2_inf.set_idx     <= pending_set;
                            c2_inf.way_sel     <= pending_way;
                            c2_inf.update_line <= {1'b1, nstate, req_tag, nsharers,
                                (nstate == DIR_M) ? requester : pending_owner, fwd_data};
                            if (req_from_nic) begin
                                c2_inf.resp_valid_o    <= 1'b1;
                                c2_inf.resp_nic_data_o <= '{msg: NMSG_DATA, we: 1'b0, is_exclusive_in: (req_op == OP_GETM),
                                    addr: req_addr, data: fwd_data, src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, req_src}};
                            end else begin
                                c2_inf.l2_l1_data_o <= '{msg_in: MSG_DATA, is_exclusive_in: (req_op == OP_GETM),
                                    addr: req_addr, data: fwd_data, requester_id: '0};
                            end
                            fill_pending <= 1'b0;
                            done         <= 1'b1;
                        end
                    end

                    DIR_INV_WAIT, DIR_EVICT_INV_WAIT: begin
                        automatic logic [7:0] inv_addr;
                        inv_addr = (pending_state == DIR_INV_WAIT) ? req_addr :
                                   {pending_set, MY_BANK_ID, c2_inf.cache_mem_out[pending_set][pending_way].tag};

                        if (pending_send[MY_BANK_ID]) begin
                            c2_inf.l2_l1_data_o <= '{msg_in: MSG_INV, is_exclusive_in: 1'b0,
                                addr: inv_addr, data: 8'b0, requester_id: '0};
                            pending_send[MY_BANK_ID] <= 1'b0;
                        end
                        begin
                            automatic logic [1:0] next_remote;
                            automatic logic       has_remote;
                            has_remote  = 1'b0;
                            next_remote = 2'd0;
                            for (int s = 0; s < 4; s++) begin
                                if (!has_remote && s != MY_BANK_ID && pending_send[s]) begin
                                    has_remote  = 1'b1;   // blocking: visible to later iterations
                                    next_remote = s[1:0];
                                end
                            end
                            if (has_remote) begin
                                c2_inf.resp_valid_o    <= 1'b1;
                                c2_inf.resp_nic_data_o <= '{msg: NMSG_INV, we: 1'b0, is_exclusive_in: 1'b0,
                                    addr: inv_addr, data: 8'b0, src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, next_remote}};
                                pending_send[next_remote] <= 1'b0;
                            end
                        end


                        if (c2_inf.l1_msg_req_in == MSG_INVACK) pending_ack[MY_BANK_ID] <= 1'b0;
                        if (c2_inf.req_valid_i && c2_inf.req_nic_pkt_i.msg == NMSG_INVACK) begin
                            c2_inf.req_ready_o                          <= 1'b1;
                            pending_ack[c2_inf.req_nic_pkt_i.src_id[1:0]] <= 1'b0;
                        end

                        if (pending_ack == '0) begin
                            if (pending_state == DIR_INV_WAIT) begin
                                automatic logic [1:0] requester;
                                requester = req_from_nic ? req_src : MY_BANK_ID;
                                c2_inf.write_en    <= 1'b1;
                                c2_inf.set_idx     <= pending_set;
                                c2_inf.way_sel     <= pending_way;
                                c2_inf.update_line <= {1'b1, DIR_M, req_tag, (4'd1 << requester), requester,
                                    c2_inf.cache_mem_out[pending_set][pending_way].data};
                                if (req_from_nic) begin
                                    c2_inf.resp_valid_o    <= 1'b1;
                                    c2_inf.resp_nic_data_o <= '{msg: NMSG_DATA, we: 1'b0, is_exclusive_in: 1'b1,
                                        addr: req_addr, data: c2_inf.cache_mem_out[pending_set][pending_way].data,
                                        src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, req_src}};
                                end else begin
                                    c2_inf.l2_l1_data_o <= '{msg_in: MSG_DATA, is_exclusive_in: 1'b1,
                                        addr: req_addr, data: c2_inf.cache_mem_out[pending_set][pending_way].data, requester_id: '0};
                                end
                                fill_pending <= 1'b0;
                                done         <= 1'b1;
                            end
                            else begin
                                pending_state <= DIR_MEM_WAIT;
                            end
                        end
                    end

                    DIR_EVICT_FWD_WAIT: begin

                        automatic logic         put_seen;
                        automatic l1_msg_out_t  put_msg;
                        automatic logic [7:0]   put_data;
                        if (pending_owner == MY_BANK_ID) begin
                            put_seen = (c2_inf.l1_msg_req_in == MSG_PUTM) || (c2_inf.l1_msg_req_in == MSG_PUTE);
                            put_msg  = c2_inf.l1_msg_req_in;
                            put_data = c2_inf.req_data_out;
                        end else begin
                            put_seen = c2_inf.req_valid_i &&
                                       (c2_inf.req_nic_pkt_i.msg == NMSG_PUTM || c2_inf.req_nic_pkt_i.msg == NMSG_PUTE) &&
                                       (c2_inf.req_nic_pkt_i.src_id[1:0] == pending_owner);
                            put_msg  = (c2_inf.req_nic_pkt_i.msg == NMSG_PUTM) ? MSG_PUTM : MSG_PUTE;
                            put_data = c2_inf.req_nic_pkt_i.data;
                        end
                        if (put_seen) begin
                            if (pending_owner != MY_BANK_ID) c2_inf.req_ready_o <= 1'b1;
                            evict_wb_data <= put_data;
                            evict_wb_we   <= (put_msg == MSG_PUTM);
                            pending_state <= DIR_EVICT_WB;
                        end
                    end

                    DIR_EVICT_WB: begin
                        if (!mem_req_sent) begin
                            c2_inf.resp_valid_o    <= 1'b1;
                            c2_inf.resp_nic_data_o <= '{msg: NMSG_MEM_REQ, we: evict_wb_we, is_exclusive_in: 1'b0,
                                addr: {pending_set, MY_BANK_ID, c2_inf.cache_mem_out[pending_set][pending_way].tag},
                                data: evict_wb_data,
                                src_id: {1'b0, MY_BANK_ID}, dest_id: MEM_ID};
                            mem_req_sent <= 1'b1;
                        end
                        else if (c2_inf.req_valid_i && c2_inf.req_nic_pkt_i.msg == NMSG_MEM_DATA &&
                                 c2_inf.req_nic_pkt_i.src_id == MEM_ID) begin
                            c2_inf.req_ready_o <= 1'b1;
                            c2_inf.write_en    <= 1'b1;
                            c2_inf.set_idx     <= pending_set;
                            c2_inf.way_sel     <= pending_way;
                            c2_inf.update_line <= {1'b0, DIR_I, req_tag, 4'b0, 2'b0, 8'b0};
                            pending_state <= DIR_MEM_WAIT;
                            mem_req_sent  <= 1'b0;
                        end
                    end

                    default: begin
                        fill_pending <= 1'b0;
                        done         <= 1'b1;
                    end
                    endcase
                  end

        L2_SNOOP : begin
                    if (!snoop_sent) begin
                        c2_inf.l2_l1_data_o <= '{
                            msg_in: (pending_snoop_msg == NMSG_FWD_GETS) ? MSG_FWD_GETS :
                                    (pending_snoop_msg == NMSG_FWD_GETM) ? MSG_FWD_GETM : MSG_INV,
                            is_exclusive_in: 1'b0, addr: req_addr, data: 8'b0, requester_id: req_src};
                        snoop_sent <= 1'b1;
                    end
                    else if (c2_inf.l1_msg_req_in == MSG_DATAFWD || c2_inf.l1_msg_req_in == MSG_PUTM ||
                             c2_inf.l1_msg_req_in == MSG_PUTE    || c2_inf.l1_msg_req_in == MSG_INVACK) begin
                        c2_inf.resp_valid_o    <= 1'b1;
                        c2_inf.resp_nic_data_o <= '{
                            msg: (c2_inf.l1_msg_req_in == MSG_DATAFWD) ? NMSG_DATAFWD :
                                 (c2_inf.l1_msg_req_in == MSG_PUTM)    ? NMSG_PUTM    :
                                 (c2_inf.l1_msg_req_in == MSG_PUTE)    ? NMSG_PUTE    : NMSG_INVACK,
                            we: 1'b0, is_exclusive_in: 1'b0, addr: req_addr, data: c2_inf.req_data_out,
                            src_id: {1'b0, MY_BANK_ID}, dest_id: {1'b0, req_src}};
                        done       <= 1'b1;
                        snoop_sent <= 1'b0;
                    end
                  end

        L2_DONE : begin
                    done <= 1'b0;
                    c2_inf.write_en <= 1'b0;
                    if (!fill_pending) begin
                        pending_state <= DIR_I;
                        pending_set   <= '0;
                        pending_way   <= '0;
                        pending_owner <= '0;
                        pending_send  <= '0;
                        pending_ack   <= '0;
                        req_from_nic  <= 1'b0;
                        req_src       <= '0;
                    end
                  end

        endcase
        end
    end

endmodule
