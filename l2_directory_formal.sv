module l2_directory_formal;
    typedef enum logic [1:0] {DIR_I=2'd0, DIR_E=2'd1, DIR_S=2'd2, DIR_M=2'd3} dir_state_t;
    typedef enum logic [1:0] {REQ_NONE=2'd0, REQ_GETS=2'd1, REQ_GETM=2'd2} req_t;

    logic clk;
    logic rst;
    logic req_valid;
    req_t req;
    logic [1:0] requester;

    dir_state_t state_q, state_d;
    logic valid_q, valid_d;
    logic [1:0] owner_q, owner_d;
    logic [3:0] sharers_q, sharers_d;

    always @(posedge clk) begin
        if ($initstate)
            assume(rst);
    end

    function automatic logic [3:0] requester_mask(input logic [1:0] id);
        requester_mask = (4'b0001 << id);
    endfunction

    always_comb begin
        state_d   = state_q;
        valid_d   = valid_q;
        owner_d   = owner_q;
        sharers_d = sharers_q;

        if (!rst && req_valid) begin
            case (req)
                REQ_GETS: begin
                    case (state_q)
                        DIR_I: begin
                            valid_d   = 1'b1;
                            state_d   = DIR_E;
                            owner_d   = requester;
                            sharers_d = requester_mask(requester);
                        end
                        DIR_E, DIR_M: begin
                            if (owner_q == requester) begin
                                valid_d   = 1'b1;
                                state_d   = state_q;
                                sharers_d = requester_mask(owner_q);
                            end else begin
                                valid_d   = 1'b1;
                                state_d   = DIR_S;
                                sharers_d = sharers_q | requester_mask(requester);
                            end
                        end
                        DIR_S: begin
                            valid_d   = 1'b1;
                            state_d   = DIR_S;
                            sharers_d = sharers_q | requester_mask(requester);
                        end
                        default: begin
                            valid_d = 1'b0;
                            state_d = DIR_I;
                            sharers_d = '0;
                        end
                    endcase
                end
                REQ_GETM: begin
                    valid_d   = 1'b1;
                    state_d   = DIR_M;
                    owner_d   = requester;
                    sharers_d = requester_mask(requester);
                end
                default: ;
            endcase
        end

        if (rst) begin
            valid_d   = 1'b0;
            state_d   = DIR_I;
            owner_d   = '0;
            sharers_d = '0;
        end
    end

    always_ff @(posedge clk) begin
        state_q   <= state_d;
        valid_q   <= valid_d;
        owner_q   <= owner_d;
        sharers_q <= sharers_d;
    end

    // Directory safety invariants: no invalid state may be advertised.
    always @(posedge clk) begin
        if (!rst) begin
            assert(valid_q || state_q == DIR_I);
            assert(valid_q || sharers_q == 4'b0);
            assert(state_q == DIR_I || sharers_q != 4'b0);
            assert(state_q == DIR_E || state_q == DIR_M || state_q == DIR_S || state_q == DIR_I);
            if (state_q == DIR_E || state_q == DIR_M)
                assert(sharers_q == requester_mask(owner_q));
            if (state_q == DIR_S)
                assert(sharers_q != 4'b0);
        end
    end
endmodule
