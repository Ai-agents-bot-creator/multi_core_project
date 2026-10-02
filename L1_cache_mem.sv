package L1_cache_mem;

typedef enum logic [3:0]{
    INVALID,IS_D,IM_D,SHARED,SM_D,EXCLUSIVE,EI_A,MODIFIED,MI_A
} MESI_STATES_t;

typedef struct packed{
    logic valid;
    MESI_STATES_t C_tag;
    logic [3:0]tag;
    logic [7:0]data;
}l1_cache_line_t;

typedef enum logic [2:0] {
    IDLE,COMPARE,ALLOCATE,DONE,SNOOP,WRITEBACK
} C_STATES_t;

typedef enum logic [3:0] {
    MSG_GETS,
    MSG_GETM,
    MSG_PUTE,
    MSG_PUTM,
    MSG_UNBLOCK,
    MSG_INVACK,
    MSG_DATAFWD,
    MSG_ACK,
    MSG_L1_NONE
} l1_msg_out_t;

typedef enum logic [2:0] {
    MSG_FWD_GETS,
    MSG_FWD_GETM,
    MSG_INV,
    MSG_DATA,
    MSG_NONE
} l1_msg_in_t;


typedef enum logic [2:0] { ACTION_HIT, ACTION_STALL_TRANSIENT, ACTION_MISS, ACTION_UPGRADE ,ACTION_ACK_VACUOUS,ACTION_INVALIDATE,ACTION_FORWARD} l1_action_t;

typedef struct packed {
    l1_action_t   action;
     l1_msg_out_t  msg_to_send;
     l1_msg_out_t msg_to_dir;
    MESI_STATES_t next_state;
} l1_decision_t;
endpackage
