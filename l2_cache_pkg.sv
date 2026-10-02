package l2_cache_pkg;
import L1_cache_mem::*;

    typedef enum logic [3:0] {
        DIR_I, DIR_S, DIR_E, DIR_M,
        DIR_MEM_WAIT, DIR_FWD_WAIT, DIR_INV_WAIT,
        DIR_EVICT_INV_WAIT, DIR_EVICT_FWD_WAIT, DIR_EVICT_WB,
        PROXY_WAIT
    } dir_state_t;

    typedef struct packed {
        logic        valid;
        dir_state_t  C_tag;
        logic [3:0]  tag;
        logic [3:0]  sharers;
        logic [1:0]  owner_id;
        logic [7:0]  data;
    } l2_cache_line_t;

    typedef enum logic [2:0] {
        L2_IDLE, L2_COMPARE, L2_ALLOCATE, L2_DONE, L2_SNOOP
    } L2_STATES_t;

    typedef enum logic [3:0] {
        NMSG_GETS, NMSG_GETM, NMSG_PUTE, NMSG_PUTM,
        NMSG_UNBLOCK, NMSG_INVACK, NMSG_DATAFWD, NMSG_ACK,
        NMSG_FWD_GETS, NMSG_FWD_GETM, NMSG_INV, NMSG_DATA,
        NMSG_MEM_REQ, NMSG_MEM_DATA,
        NMSG_NONE
    } l2_nic_msg_t;


    typedef struct packed {
        l2_nic_msg_t msg;
        logic        we;
        logic        is_exclusive_in;
        logic [7:0]  addr;
        logic [7:0]  data;
        logic [2:0]  src_id;
        logic [2:0]  dest_id;
    } l2_nic_pkt_t;

   typedef struct packed {
    l1_msg_in_t  msg_in;
    logic is_exclusive_in;
    logic [7:0]addr;
    logic [7:0]data;
    logic [1:0]requester_id;
}l2_li_data_t;

    typedef enum logic [2:0] {
        L2_ACTION_HIT,
        L2_ACTION_UPGRADE_INV,     // DIR_S + GetM
        L2_ACTION_FORWARD,         // DIR_E/DIR_M
        L2_ACTION_MISS,            // no tag match,
        L2_ACTION_EVICT_INV,       // no tag match, victim is DIR_S: invalidate its sharers first
        L2_ACTION_EVICT_RECALL,    // no tag match, victim is DIR_E/DIR_M: recall from owner first
        L2_ACTION_PUT_ACK,         // PutM/PutE: just ack
        L2_ACTION_NONE
    } l2_action_t;

    typedef struct packed {
        l2_action_t   action;
        l1_msg_in_t   msg_to_send;
        dir_state_t   next_state;
        logic [1:0]   target_id;
    } l2_decision_t;

endpackage
