/* ****************************************************************************
  This Source Code Form is subject to the terms of the
  Open Hardware Description License, v. 1.0. If a copy
  of the OHDL was not distributed with this file, You
  can obtain one at http://juliusbaxter.net/ohdl/ohdl.txt

  Description: Cappuccino decode to execute module.
  - Decode to execute stage signal passing.
  - Branches are resolved (in decode stage).
  - Hazards that can not be resolved by bypassing are detected and
    bubbles are inserted on such conditions.

  Generate valid signal when stage is done.

  Copyright (C) 2012 Julius Baxter <juliusbaxter@gmail.com>
  Copyright (C) 2013 Stefan Kristiansson <stefan.kristiansson@saunalahti.fi>

***************************************************************************** */

`include "mor1kx-defines.v"

module mor1kx_decode_execute_cappuccino
  #(
    parameter OPTION_OPERAND_WIDTH = 32,
    parameter OPTION_RESET_PC = {{(OPTION_OPERAND_WIDTH-13){1'b0}},
				 `OR1K_RESET_VECTOR,8'd0},

    parameter OPTION_RF_ADDR_WIDTH = 5,

    parameter FEATURE_SYSCALL = "ENABLED",
    parameter FEATURE_TRAP = "ENABLED",
    parameter FEATURE_DELAY_SLOT = "ENABLED",

    parameter FEATURE_INBUILT_CHECKERS = "ENABLED"
    )
   (
    input 				  clk,
    input 				  rst,

    // pipeline control signal in
    input 				  padv_i,
    input [OPTION_OPERAND_WIDTH-1:0] 	  pc_decode_i,

    // input from register file
    input [OPTION_OPERAND_WIDTH-1:0] 	  decode_rfb_i,
    input [OPTION_OPERAND_WIDTH-1:0] 	  execute_rfb_i,

    // input from execute stage
    input 				  flag_i,
    input 				  flag_set_i,
    input 				  flag_clear_i,

    input 				  pipeline_flush_i,

    // ALU related inputs from decode
    input [`OR1K_ALU_OPC_WIDTH-1:0] 	  decode_opc_alu_i,
    input [`OR1K_ALU_OPC_WIDTH-1:0] 	  decode_opc_alu_secondary_i,

    input [`OR1K_IMM_WIDTH-1:0] 	  decode_imm16_i,
    input [OPTION_OPERAND_WIDTH-1:0] 	  decode_immediate_i,
    input 				  decode_immediate_sel_i,

    //  ALU related outputs to execute
    output reg [`OR1K_ALU_OPC_WIDTH-1:0]  execute_opc_alu_o,
    output reg [`OR1K_ALU_OPC_WIDTH-1:0]  execute_opc_alu_secondary_o,

    output reg [`OR1K_IMM_WIDTH-1:0] 	  execute_imm16_o,
    output reg [OPTION_OPERAND_WIDTH-1:0] execute_immediate_o,
    output reg 				  execute_immediate_sel_o,

    // Adder control logic from decode
    input 				  decode_adder_do_sub_i,
    input 				  decode_adder_do_carry_i,

    // Adder control logic to execute
    output reg 				  execute_adder_do_sub_o,
    output reg 				  execute_adder_do_carry_o,

    // Upper 10 bits of immediate for jumps and branches
    input [9:0] 			  decode_immjbr_upper_i,
    output reg [9:0] 			  execute_immjbr_upper_o,

    // GPR numbers
    output reg [OPTION_RF_ADDR_WIDTH-1:0] execute_rfd_adr_o,
    input [OPTION_RF_ADDR_WIDTH-1:0] 	  decode_rfd_adr_i,
    input [OPTION_RF_ADDR_WIDTH-1:0] 	  decode_rfa_adr_i,
    input [OPTION_RF_ADDR_WIDTH-1:0] 	  decode_rfb_adr_i,
    input [OPTION_RF_ADDR_WIDTH-1:0] 	  ctrl_rfd_adr_i,
    input 				  ctrl_op_lsu_load_i,
    input 				  ctrl_op_mfspr_i,

    // Control signal inputs from decode stage
    input 				  decode_rf_wb_i,

    input 				  decode_op_alu_i,

    input 				  decode_op_setflag_i,

    input 				  decode_op_jbr_i,
    input 				  decode_op_jr_i,
    input 				  decode_op_jal_i,
    input 				  decode_op_branch_i,

    input 				  decode_op_lsu_load_i,
    input 				  decode_op_lsu_store_i,
    input [1:0] 			  decode_lsu_length_i,
    input 				  decode_lsu_zext_i,

    input 				  decode_op_mfspr_i,
    input 				  decode_op_mtspr_i,

    input 				  decode_op_rfe_i,
    input 				  decode_op_add_i,
    input 				  decode_op_mul_i,
    input 				  decode_op_mul_signed_i,
    input 				  decode_op_mul_unsigned_i,
    input 				  decode_op_div_i,
    input 				  decode_op_div_signed_i,
    input 				  decode_op_div_unsigned_i,
    input 				  decode_op_shift_i,
    input 				  decode_op_ffl1_i,
    input 				  decode_op_movhi_i,

    input [`OR1K_OPCODE_WIDTH-1:0] 	  decode_opc_insn_i,

    // Control signal outputs to execute stage
    output reg 				  execute_rf_wb_o,

    output reg 				  execute_op_alu_o,

    output reg 				  execute_op_setflag_o,

    output reg 				  execute_op_jbr_o,
    output reg 				  execute_op_jr_o,
    output reg 				  execute_op_jal_o,
    output reg 				  execute_op_branch_o,

    output reg 				  execute_op_lsu_load_o,
    output reg 				  execute_op_lsu_store_o,
    output reg [1:0] 			  execute_lsu_length_o,
    output reg 				  execute_lsu_zext_o,

    output reg 				  execute_op_mfspr_o,
    output reg 				  execute_op_mtspr_o,

    output reg 				  execute_op_rfe_o,
    output reg 				  execute_op_add_o,
    output reg 				  execute_op_mul_o,
    output reg 				  execute_op_mul_signed_o,
    output reg 				  execute_op_mul_unsigned_o,
    output reg 				  execute_op_div_o,
    output reg 				  execute_op_div_signed_o,
    output reg 				  execute_op_div_unsigned_o,
    output reg 				  execute_op_shift_o,
    output reg 				  execute_op_ffl1_o,
    output reg 				  execute_op_movhi_o,

    output reg [OPTION_OPERAND_WIDTH-1:0] execute_jal_result_o,

    output reg [`OR1K_OPCODE_WIDTH-1:0]   execute_opc_insn_o,

    // branch detection
    output 				  decode_branch_o,
    output [OPTION_OPERAND_WIDTH-1:0] 	  decode_branch_target_o,

    // exceptions in
    input 				  decode_except_ibus_err_i,
    input 				  decode_except_itlb_miss_i,
    input 				  decode_except_ipagefault_i,
    input 				  decode_except_illegal_i,
    input 				  decode_except_syscall_i,
    input 				  decode_except_trap_i,

    // exception output -
    output reg 				  execute_except_ibus_err_o,
    output reg 				  execute_except_itlb_miss_o,
    output reg 				  execute_except_ipagefault_o,
    output reg 				  execute_except_illegal_o,
    output reg 				  execute_except_ibus_align_o,
    output reg 				  execute_except_syscall_o,
    output reg 				  execute_except_trap_o,

    output reg [OPTION_OPERAND_WIDTH-1:0] pc_execute_o,

    // output is valid, signal
    output reg 				  decode_valid_o,

    output 				  decode_bubble_o,
    output reg 				  execute_bubble_o
    );

   wire   ctrl_to_decode_interlock;
   wire   branch_to_imm;
   wire   branch_to_reg;

   wire   decode_except_ibus_align;

   reg 	  flag_r;
   wire   flag;

   reg 	  pipeline_flush_r;

   // Op control signals to execute stage
   always @(posedge clk `OR_ASYNC_RST)
     if (rst) begin
	execute_op_alu_o <= 1'b0;
	execute_op_add_o <= 1'b0;
	execute_op_mul_o <= 1'b0;
	execute_op_mul_signed_o <= 1'b0;
	execute_op_mul_unsigned_o <= 1'b0;
	execute_op_div_o <= 1'b0;
	execute_op_div_signed_o <= 1'b0;
	execute_op_div_unsigned_o <= 1'b0;
	execute_op_shift_o <= 1'b0;
	execute_op_ffl1_o <= 1'b0;
	execute_op_movhi_o <= 1'b0;
	execute_op_mfspr_o <= 1'b0;
	execute_op_mtspr_o <= 1'b0;
	execute_op_lsu_load_o <= 1'b0;
	execute_op_lsu_store_o <= 1'b0;
	execute_op_setflag_o <= 1'b0;
	execute_op_jbr_o <= 1'b0;
	execute_op_jr_o <= 1'b0;
	execute_op_jal_o <= 1'b0;
	execute_op_branch_o <= 0;
     end else if (pipeline_flush_i) begin
	execute_op_alu_o <= 1'b0;
	execute_op_add_o <= 1'b0;
	execute_op_mul_o <= 1'b0;
	execute_op_mul_signed_o <= 1'b0;
	execute_op_mul_unsigned_o <= 1'b0;
	execute_op_div_o <= 1'b0;
	execute_op_div_signed_o <= 1'b0;
	execute_op_div_unsigned_o <= 1'b0;
	execute_op_shift_o <= 1'b0;
	execute_op_ffl1_o <= 1'b0;
	execute_op_movhi_o <= 1'b0;
	execute_op_lsu_load_o <= 1'b0;
	execute_op_lsu_store_o <= 1'b0;
	execute_op_setflag_o <= 1'b0;
	execute_op_jbr_o <= 1'b0;
	execute_op_jr_o <= 1'b0;
	execute_op_jal_o <= 1'b0;
	execute_op_branch_o <= 1'b0;
     end else if (padv_i) begin
	execute_op_alu_o <= decode_op_alu_i;
	execute_op_add_o <= decode_op_add_i;
	execute_op_mul_o <= decode_op_mul_i;
	execute_op_mul_signed_o <= decode_op_mul_signed_i;
	execute_op_mul_unsigned_o <= decode_op_mul_unsigned_i;
	execute_op_div_o <= decode_op_div_i;
	execute_op_div_signed_o <= decode_op_div_signed_i;
	execute_op_div_unsigned_o <= decode_op_div_unsigned_i;
	execute_op_shift_o <= decode_op_shift_i;
	execute_op_ffl1_o <= decode_op_ffl1_i;
	execute_op_movhi_o <= decode_op_movhi_i;
	execute_op_mfspr_o <= decode_op_mfspr_i;
	execute_op_mtspr_o <= decode_op_mtspr_i;
	execute_op_lsu_load_o <= decode_op_lsu_load_i;
	execute_op_lsu_store_o <= decode_op_lsu_store_i;
	execute_op_setflag_o <= decode_op_setflag_i;
	execute_op_jbr_o <= decode_op_jbr_i;
	execute_op_jr_o <= decode_op_jr_i;
	execute_op_jal_o <= decode_op_jal_i;
	execute_op_branch_o <= decode_op_branch_i;
	if (decode_bubble_o) begin
	   execute_op_alu_o <= 1'b0;
	   execute_op_add_o <= 1'b0;
	   execute_op_mul_o <= 1'b0;
	   execute_op_mul_signed_o <= 1'b0;
	   execute_op_mul_unsigned_o <= 1'b0;
	   execute_op_div_o <= 1'b0;
	   execute_op_div_signed_o <= 1'b0;
	   execute_op_div_unsigned_o <= 1'b0;
	   execute_op_shift_o <= 1'b0;
	   execute_op_ffl1_o <= 1'b0;
	   execute_op_movhi_o <= 1'b0;
	   execute_op_mtspr_o <= 1'b0;
	   execute_op_mfspr_o <= 1'b0;
	   execute_op_lsu_load_o <= 1'b0;
	   execute_op_lsu_store_o <= 1'b0;
	   execute_op_setflag_o <= 1'b0;
	   execute_op_jbr_o <= 1'b0;
	   execute_op_jr_o <= 1'b0;
	   execute_op_jal_o <= 1'b0;
	   execute_op_branch_o <= 1'b0;
	end
     end

   // rfe is a special case, instead of pushing the pipeline full
   // of nops on a decode_bubble_o, we push it full of rfes.
   // The reason for this is that we need the rfe to reach control
   // stage so it will cause the branch.
   // It will clear itself by the pipeline_flush_i that the rfe
   // will generate.
   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_op_rfe_o <= 0;
     else if (pipeline_flush_i)
       execute_op_rfe_o <= 0;
     else if (padv_i)
       execute_op_rfe_o <= decode_op_rfe_i;

   always @(posedge clk `OR_ASYNC_RST)
     if (rst) begin
	execute_rf_wb_o <= 0;
     end else if (pipeline_flush_i) begin
	execute_rf_wb_o <= 0;
     end else if (padv_i) begin
	execute_rf_wb_o <= decode_rf_wb_i;
	if (decode_bubble_o)
	  execute_rf_wb_o <= 0;
     end

   always @(posedge clk)
     if (padv_i)
       execute_rfd_adr_o <= decode_rfd_adr_i;

   always @(posedge clk)
     if (padv_i) begin
	execute_lsu_length_o <= decode_lsu_length_i;
	execute_lsu_zext_o <= decode_lsu_zext_i;
     end

   always @(posedge clk)
     if (padv_i) begin
	execute_imm16_o <= decode_imm16_i;
	execute_immediate_o <= decode_immediate_i;
	execute_immediate_sel_o <= decode_immediate_sel_i;
     end

   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_immjbr_upper_o <= 0;
     else if (padv_i )
       execute_immjbr_upper_o <= decode_immjbr_upper_i;

   always @(posedge clk)
     if (padv_i) begin
	execute_opc_alu_o <= decode_opc_alu_i;
	execute_opc_alu_secondary_o <= decode_opc_alu_secondary_i;
     end

   always @(posedge clk `OR_ASYNC_RST)
     if (rst) begin
	execute_opc_insn_o <= `OR1K_OPCODE_NOP;
     end else if (pipeline_flush_i) begin
	execute_opc_insn_o <= `OR1K_OPCODE_NOP;
     end else if (padv_i) begin
	execute_opc_insn_o <= decode_opc_insn_i;
	if (decode_bubble_o)
	  execute_opc_insn_o <= `OR1K_OPCODE_NOP;
     end

   always @(posedge clk `OR_ASYNC_RST)
     if (rst) begin
	execute_adder_do_sub_o <= 1'b0;
	execute_adder_do_carry_o <= 1'b0;
     end else if (pipeline_flush_i) begin
	execute_adder_do_sub_o <= 1'b0;
	execute_adder_do_carry_o <= 1'b0;
     end else if (padv_i) begin
	execute_adder_do_sub_o <= decode_adder_do_sub_i;
	execute_adder_do_carry_o <= decode_adder_do_carry_i;
	if (decode_bubble_o) begin
	   execute_adder_do_sub_o <= 1'b0;
	   execute_adder_do_carry_o <= 1'b0;
	end
     end

   // Decode for system call exception
   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_except_syscall_o <= 0;
     else if (padv_i && FEATURE_SYSCALL=="ENABLED")
       execute_except_syscall_o <= decode_except_syscall_i;

   // Decode for system call exception
   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_except_trap_o <= 0;
     else if (padv_i && FEATURE_TRAP=="ENABLED")
       execute_except_trap_o <= decode_except_trap_i;

   // Decode Illegal instruction
   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_except_illegal_o <= 0;
     else if (padv_i)
       execute_except_illegal_o <= decode_except_illegal_i;

   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_except_ibus_err_o <= 1'b0;
     else if (padv_i)
       execute_except_ibus_err_o <= decode_except_ibus_err_i;

   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_except_itlb_miss_o <= 1'b0;
     else if (padv_i)
       execute_except_itlb_miss_o <= decode_except_itlb_miss_i;

   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_except_ipagefault_o <= 1'b0;
     else if (padv_i)
       execute_except_ipagefault_o <= decode_except_ipagefault_i;

   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_except_ibus_align_o <= 1'b0;
     else if (padv_i)
       execute_except_ibus_align_o <= decode_except_ibus_align;

   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       decode_valid_o <= 0;
     else
       decode_valid_o <= padv_i;

   always @(posedge clk `OR_ASYNC_RST)
     if (padv_i)
       pc_execute_o <= pc_decode_i;

   // Flag calculation, we get the flag_set_i and flag_clear_i straight from
   // execute stage, and we keep track of the value.
   always @(posedge clk)
     pipeline_flush_r <= pipeline_flush_i;

   always @(posedge clk)
     if (pipeline_flush_r)
       flag_r <= flag_i;
     else if (flag_set_i)
       flag_r <= 1;
     else if (flag_clear_i)
       flag_r <= 0;

   assign flag = pipeline_flush_r ? flag_i :
		 (!flag_clear_i & flag_r) | flag_set_i;

   // Branch detection
   assign ctrl_to_decode_interlock = (ctrl_op_lsu_load_i | ctrl_op_mfspr_i) &
				     (decode_rfb_adr_i == ctrl_rfd_adr_i);

   assign branch_to_imm = (decode_op_jbr_i &
			   // l.j/l.jal
			   (!(|decode_opc_insn_i[2:1]) |
			    // l.bf/bnf and flag is right
			    (decode_opc_insn_i[2] == flag)));

   assign branch_to_reg = decode_op_jr_i & !ctrl_to_decode_interlock;

   assign decode_branch_o = (branch_to_imm | branch_to_reg) &
			    !pipeline_flush_i & !decode_bubble_o;

   assign decode_branch_target_o = branch_to_imm ?
				   pc_decode_i + {{4{decode_immjbr_upper_i[9]}},
						  decode_immjbr_upper_i,
						  decode_imm16_i,2'b00} :
				   // If a bubble have been pushed out to get
				   // the instruction that will write the
				   // branch target to control stage, then we
				   // need to use the register result from
				   // execute stage instead of decode stage.
				   execute_bubble_o | execute_op_jr_o ?
				   execute_rfb_i : decode_rfb_i;

   assign decode_except_ibus_align = decode_branch_o &
				     (|decode_branch_target_o[1:0]);

   // Calculate the link register result
   // TODO: investigate if the ALU adder can be used for this without
   // introducing critical paths
   always @(posedge clk)
     if (padv_i)
       execute_jal_result_o <= FEATURE_DELAY_SLOT == "ENABLED" ?
			       pc_decode_i + 8 :
			       pc_decode_i + 4;

   // Detect the situation where there is an instruction in execute stage
   // that will produce it's result in control stage (i.e. load and mfspr),
   // and an instruction currently in decode stage needing it's result as
   // input in execute stage.
   // Also detect the situation where there is a jump to register in decode
   // stage and an instruction in execute stage that will write to that
   // register.
   //
   // A bubble is also inserted when an rfe instruction is in decode stage,
   // the main purpose of this is to stall fetch while the rfe is propagating
   // up to ctrl stage.

   assign decode_bubble_o = ((execute_op_lsu_load_o | execute_op_mfspr_o) &
			     (decode_rfa_adr_i == execute_rfd_adr_o ||
			      decode_rfb_adr_i == execute_rfd_adr_o) |
			     decode_op_jr_i &
			     (ctrl_to_decode_interlock |
			      (decode_rfb_adr_i == execute_rfd_adr_o)) |
			     decode_op_rfe_i) & padv_i;

   always @(posedge clk `OR_ASYNC_RST)
     if (rst)
       execute_bubble_o <= 0;
     else if (pipeline_flush_i)
       execute_bubble_o <= 0;
     else if (padv_i)
       execute_bubble_o <= decode_bubble_o;

   // synthesis translate_off
   generate
      if (FEATURE_INBUILT_CHECKERS != "NONE") begin
	 // assert on l.bnf/l.bf and flag is 'x'
	 always @(posedge clk)
	    if (padv_i & !rst & !pipeline_flush_i &
		decode_op_jbr_i & (|decode_opc_insn_i[2:1]) &
		flag === 1'bx) begin
	       $display("ERROR: flag === 'x' on l.b(n)f");
	       $finish();
	    end

      end
   endgenerate
   // synthesis translate_on

endmodule // mor1kx_decode_execute_cappuccino
