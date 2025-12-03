// OpenRAM SRAM model
// Words: 256
// Word size: 32
// Write size: 8
// Pseudo-Dual Port: 1 Read/Write Port + 1 Read-only Port

`timescale 1ns/1ps

module sky130_sram_1kbyte_1rw1r_32x256_8(
`ifdef USE_POWER_PINS
    vccd1,
    vssd1,
`endif
// Port 0: RW (Read/Write)
    clk0,csb0,web0,wmask0,addr0,din0,dout0,
// Port 1: R (Read-only)
    clk1,csb1,addr1,dout1
  );

  parameter NUM_WMASKS = 4 ;
  parameter DATA_WIDTH = 32 ;
  parameter ADDR_WIDTH = 8 ;
  parameter RAM_DEPTH = 1 << ADDR_WIDTH;  // 256 words
  parameter DELAY = 3 ;
  parameter VERBOSE = 1 ; //Set to 0 to only display warnings
  parameter T_HOLD = 1 ; //Delay to hold dout value after posedge

`ifdef USE_POWER_PINS
    inout vccd1;
    inout vssd1;
`endif
  
  // Port 0: RW
  input  clk0;                          // clock
  input  csb0;                          // active low chip select
  input  web0;                          // active low write control
  input  [NUM_WMASKS-1:0]   wmask0;    // write mask (byte enable)
  input  [ADDR_WIDTH-1:0]  addr0;      // address
  input  [DATA_WIDTH-1:0]  din0;       // data input
  output [DATA_WIDTH-1:0] dout0;       // data output
  
  // Port 1: R
  input  clk1;                          // clock
  input  csb1;                          // active low chip select
  input  [ADDR_WIDTH-1:0]  addr1;      // address
  output [DATA_WIDTH-1:0] dout1;       // data output

  // Port 0 Registers
  reg  csb0_reg;
  reg  web0_reg;
  reg [NUM_WMASKS-1:0]   wmask0_reg;
  reg [ADDR_WIDTH-1:0]  addr0_reg;
  reg [DATA_WIDTH-1:0]  din0_reg;
  reg [DATA_WIDTH-1:0]  dout0;

  // Port 1 Registers
  reg  csb1_reg;
  reg [ADDR_WIDTH-1:0]  addr1_reg;
  reg [DATA_WIDTH-1:0]  dout1;

  // Memory Array
  reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

  // Port 0: Sample inputs on posedge
  always @(posedge clk0) begin
    csb0_reg = csb0;
    web0_reg = web0;
    wmask0_reg = wmask0;
    addr0_reg = addr0;
    din0_reg = din0;
    #(T_HOLD) dout0 = 32'bx;
    
    if ( !csb0_reg && web0_reg && VERBOSE ) 
      $display($time," Reading %m addr0=%b dout0=%h",addr0_reg,mem[addr0_reg]);
    if ( !csb0_reg && !web0_reg && VERBOSE )
      $display($time," Writing %m addr0=%b din0=%h wmask0=%b",addr0_reg,din0_reg,wmask0_reg);
  end

  // Port 1: Sample inputs on posedge
  always @(posedge clk1) begin
    csb1_reg = csb1;
    addr1_reg = addr1;
    
    // Detect simultaneous read/write conflict
    if (!csb0 && !web0 && !csb1 && (addr0 == addr1))
      $display($time," WARNING: Simultaneous write (port0) and read (port1) at addr=%h!",addr0);
    
    #(T_HOLD) dout1 = 32'bx;
    if ( !csb1_reg && VERBOSE ) 
      $display($time," Reading %m addr1=%b dout1=%h",addr1_reg,mem[addr1_reg]);
  end

  // Port 0: Write Operation
  // Write on negedge when web0=0, csb0=0
  always @ (negedge clk0) begin : MEM_WRITE0
    if ( !csb0_reg && !web0_reg ) begin
      if (wmask0_reg[0])
        mem[addr0_reg][7:0] = din0_reg[7:0];
      if (wmask0_reg[1])
        mem[addr0_reg][15:8] = din0_reg[15:8];
      if (wmask0_reg[2])
        mem[addr0_reg][23:16] = din0_reg[23:16];
      if (wmask0_reg[3])
        mem[addr0_reg][31:24] = din0_reg[31:24];
    end
  end

  // Port 0: Read Operation
  // Read on negedge when web0=1, csb0=0
  always @ (negedge clk0) begin : MEM_READ0
    if (!csb0_reg && web0_reg)
       dout0 <= #(DELAY) mem[addr0_reg];
  end

  // Port 1: Read Operation
  // Read on negedge when csb1=0
  always @ (negedge clk1) begin : MEM_READ1
    if (!csb1_reg)
       dout1 <= #(DELAY) mem[addr1_reg];
  end

endmodule
