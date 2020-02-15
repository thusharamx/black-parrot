
// The BlackParrot core pipeline is a mostly non-stalling pipeline, decoupled between the front-end
// and back-end.
module bp_nonsynth_core_profiler
  import bp_common_pkg::*;
  import bp_common_aviary_pkg::*;
  import bp_common_rv64_pkg::*;
  import bp_be_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_inv_cfg
    `declare_bp_proc_params(bp_params_p)

    , parameter stall_trace_file_p = "stall"

    , localparam dispatch_pkt_width_lp = `bp_be_dispatch_pkt_width(vaddr_width_p)
    , localparam commit_pkt_width_lp = `bp_be_commit_pkt_width(vaddr_width_p)
    , localparam trap_pkt_width_lp = `bp_be_trap_pkt_width(vaddr_width_p)
    )
   (input clk_i
    , input reset_i
    , input freeze_i

    , input mhartid_i

    // IF1 events
    , input fe_wait_stall

    // IF2 events
    , input itlb_miss
    , input icache_miss
    , input branch_override
 
    // Backwards ISS events
    // TODO: Differentiate between different FE cmds
    , input fe_cmd

    // ISS Stalls
    , input cmd_fence

    // ISD events
    , input branch_mispredict
    , input dependency_stall

    // ALU events

    // MUL events

    // MEM events
    , input dtlb_miss
    , input dcache_miss
    , input eret
    , input exception
    , input interrupt

    // Reservation packet
    , input [dispatch_pkt_width_lp-1:0] reservation

    // Commit packet
    , input [commit_pkt_width_lp-1:0] commit_pkt
    // Trap packet
    , input [trap_pkt_width_lp-1:0] trap_pkt
    );

  `declare_bp_be_internal_if_structs(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p);

  typedef struct packed
  {
    logic fe_wait_stall;
    logic itlb_miss;
    logic icache_miss;
    logic branch_override;
    logic fe_cmd;
    logic cmd_fence;
    logic branch_mispredict;
    logic dependency_stall;
    logic dtlb_miss;
    logic dcache_miss;
    logic eret;
    logic exception;
    logic interrupt;
    logic freeze;
  }  bp_stall_reason_s;

  localparam num_stages_p = 8;
  bp_stall_reason_s [num_stages_p-1:0] stall_stage_n, stall_stage_r;
  bp_stall_reason_s stall_reason_r;
  bsg_dff_reset
   #(.width_p($bits(bp_stall_reason_s)*num_stages_p))
   stall_pipe
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.data_i(stall_stage_n)
     ,.data_o(stall_stage_r)
     );
  assign stall_reason_r = stall_stage_r[num_stages_p-1];

  bp_be_dispatch_pkt_s reservation_r;
  bsg_dff_chain
   #(.width_p($bits(bp_be_dispatch_pkt_s))
     ,.num_stages_p(4)
     )
   reservation_pipe
    (.clk_i(clk_i)
     ,.data_i(reservation)
     ,.data_o(reservation_r)
     );

  bp_be_commit_pkt_s commit_pkt_r;
  bsg_dff_reset
   #(.width_p($bits(bp_be_commit_pkt_s)))
   commit_pipe
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.data_i(commit_pkt)
     ,.data_o(commit_pkt_r)
     );

  bp_be_trap_pkt_s trap_pkt_r;
  bsg_dff_reset
   #(.width_p($bits(bp_be_trap_pkt_s)))
   trap_pipe
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.data_i(trap_pkt)
     ,.data_o(trap_pkt_r)
     );

  always_comb
    begin
      // By default, move down the pipe
      for (integer i = 0; i < num_stages_p; i++)
        stall_stage_n[i] = (i == '0) ? '0 : stall_stage_r[i-1];

      // IF1
      stall_stage_n[0].fe_wait_stall     = fe_wait_stall;
      stall_stage_n[0].itlb_miss         = itlb_miss;
      stall_stage_n[0].icache_miss       = icache_miss;
      // Only some FE cmds affect IF1
      stall_stage_n[0].fe_cmd            = fe_cmd;

      // IF2
      stall_stage_n[1].itlb_miss         |= itlb_miss;
      stall_stage_n[1].icache_miss       |= icache_miss;
      stall_stage_n[1].branch_override   |= branch_override;
      stall_stage_n[1].fe_cmd            |= fe_cmd;

      // ISS
      stall_stage_n[2].itlb_miss         |= itlb_miss;
      stall_stage_n[2].icache_miss       |= icache_miss;
      stall_stage_n[2].cmd_fence         |= cmd_fence;
      stall_stage_n[2].branch_mispredict |= branch_mispredict;
      stall_stage_n[2].exception         |= exception;
      stall_stage_n[2].eret              |= eret;
      stall_stage_n[2].interrupt         |= interrupt;

      // ISD
      stall_stage_n[3].branch_mispredict |= branch_mispredict;
      stall_stage_n[3].dtlb_miss         |= dtlb_miss;
      stall_stage_n[3].dcache_miss       |= dcache_miss;
      stall_stage_n[3].exception         |= exception;
      stall_stage_n[3].eret              |= eret;
      stall_stage_n[3].interrupt         |= interrupt;

      // EX1
      stall_stage_n[4].branch_mispredict |= branch_mispredict;
      stall_stage_n[4].dtlb_miss         |= dtlb_miss;
      stall_stage_n[4].dcache_miss       |= dcache_miss;
      stall_stage_n[4].exception         |= exception;
      stall_stage_n[4].eret              |= eret;
      stall_stage_n[4].interrupt         |= interrupt;
      stall_stage_n[4].dependency_stall  |= dependency_stall;

      // EX2
      stall_stage_n[5].dtlb_miss         |= dtlb_miss;
      stall_stage_n[5].dcache_miss       |= dcache_miss;
      stall_stage_n[5].exception         |= exception;
      stall_stage_n[5].eret              |= eret;
      stall_stage_n[5].interrupt         |= interrupt;

      // EX3
      stall_stage_n[6].dtlb_miss         |= dtlb_miss;
      stall_stage_n[6].dcache_miss       |= dcache_miss;
      stall_stage_n[6].exception         |= exception;
      stall_stage_n[6].eret              |= eret;
      stall_stage_n[6].interrupt         |= interrupt;
    end

  integer file;
  string file_name;
  always_ff @(negedge (reset_i | freeze_i))
    begin
      file_name = $sformatf("%s_%x.trace", stall_trace_file_p, mhartid_i);
      file      = $fopen(file_name, "w");
    end


  always_ff @(negedge clk_i)
    begin
      if (commit_pkt_r.v)
        $fwrite(file, "[%t] Commit: %x\n", $time, commit_pkt_r.pc);
      if (~freeze_i & ~commit_pkt_r.v)
        $fwrite(file, "[%t] Stall: %x %p\n", $time, commit_pkt_r.pc, stall_reason_r);

      assert (commit_pkt_r.v | freeze_i | |stall_reason_r)
        else $display("No stall reason for bubble at PC: %x", commit_pkt_r.pc);
    end

endmodule

