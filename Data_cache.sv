

module Data_cache #(
  parameter AddressBits = 'd32,	// Total Number of Address Bits = 32
  parameter Sets= 'd 16* 'd 1024, // Total number of TOTAL SETS = 16K
  parameter Ways = 'd 8, // Total number of TOTAL WAYS = 8ways for data
  parameter Bytelines = 'd 64,	// Total number of bytes in cache line =64
  parameter ByteOffsetBit = $clog2 (Bytelines),	 // Number of byte offset bits n (2**n)
  parameter IndexBits = $clog2 (Sets),	// Number of byte offset bits
  parameter LRUbits = $clog2 (Ways), // Number of LRU_bits
  parameter Tagbits = AddressBits - (ByteOffsetBit + IndexBits) // Number of TAG bits
  	
)
( 

  input logic mode, Clk, rst, // Mode (likely L1 vs. L2)
  input bit dp, // data display condition
  input logic [3:0] cmd,      // Command from trace file
  input logic [31:0] Trace_address,	// Address from trace file
  output real data_read, data_write, data_hit, data_miss

);

  real dhit_ratio; 	
  // Cache state for each cache line											
  logic [LRUbits-1:0] LRU[Sets-1:0][Ways-1:0] = {default:3'b000}; // LRU bits per cache line - Default set to 000
  logic [Tagbits-1:0] TAG[Sets-1:0][Ways-1:0];	// Tag bits per cache line
  bit valid[Sets-1:0][Ways-1:0];  // Valid bits for each line
  bit dirty[Sets-1:0][Ways-1:0]; // Dirty bits for each line only for writeback condition
  bit FWT [Sets -1: 0] [Ways-1:0];  // First write-through flag

  typedef enum logic [3:0] {Modified = 4'b0000, Exclusive = 4'b0001, 
			    Shared = 4'b0010, Invalid = 4'b0011} st;
  st MESI[Sets-1 : 0][Ways-1:0]; // MESI stores the cache line's state: Modified, Exclusive, Shared, or Invalid.
  int exit = 0;
  int valid_count = 0;

  logic [ByteOffsetBit- 1 :0] byte_offset;
  logic [IndexBits-1 :0] set_index;
  logic [Tagbits -1 :0] tag_index;

  assign byte_offset = Trace_address [ByteOffsetBit-1 :0];
  assign set_index = Trace_address [ByteOffsetBit + IndexBits-1 :ByteOffsetBit];
  assign tag_index = Trace_address [AddressBits-1: ByteOffsetBit + IndexBits];
  
  always@(dp)
  begin
  Data_Output();
  Data_report();
  end
  
  always_ff @(posedge Clk or posedge rst)
    begin
      if(rst)
        begin
          data_read = 0;
          data_write = 0;
          data_hit = 0;
          data_miss = 0;
          foreach (MESI [x,y])
            begin
              TAG[x][y] = 0;
              MESI[x][y] = Invalid;
              LRU[x][y] = 3'b000;
              FWT[x][y] = 0;
              valid[x][y] = 0;
              dirty[x][y] = 0;
            end
        end

      else
        begin

          if (cmd != 2)
            begin
              case(cmd)
                0, 1, 3, 4:
                  begin
                    exit = 0;
                    for(int m=0 ; m<=7; m++) //8ways
                      begin
                        if(valid[set_index][m] == 1) // 8ways
                          valid_count = valid_count +1;
                      end

                    for (int i = 0 ; i<=7 ; i++) // 8ways
                      begin
                        if ( (valid[set_index][i] == 0) && ( TAG[set_index][i] == tag_index) )
                          begin
				if(mode == 1'b1)
                                begin
					$display("------TAG BITS MATCH, HENCE HIT-------");
                           	 	$display("------Communication with L2------");
                            		$display("Data Cache : Write to L2 <%0h>", Trace_address);
				end
                            	LRU_Updated(i);
                           	valid[set_index][i] = 1;
                           	dirty[set_index][i] = 0;
					
                         end
                     end

                    for(int m=0 ; m <= 7; m++) 
                      begin

                        ///////////////************************************ IF TAG BITS MATCH - HIT *********************************/////////////////////
                        if((exit==0 && valid[set_index][m] == 1) && ( TAG[set_index][m] == tag_index) )
                          begin
                            exit = 1;
                            data_hit = data_hit+1;
                            $display("------TAG BITS MATCH, HENCE HIT-------");

                            //////////////////////////////--------------------MODIFIED STATE -----------------------///////////////////////////////////

                            if (MESI[set_index][m] == Modified)
                              begin
                                if (cmd == 0) 				// Read data request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modified;
                                    data_read = data_read + 1;
                                    LRU_Updated(m);
                                    dirty[set_index][m]=1;
                                  end

                                else if (cmd == 1)			// Write data request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modified;
                                    data_write = data_write + 1;
                                    LRU_Updated(m);
				    
                                    if (FWT [set_index][m]==0)
                                      begin
                                        if(mode == 1'b1)
                                          begin
                                            $display("------Communication with L2------");
                                            $display("Data Cache : Write to L2 <%0h>", Trace_address);
                                            
                                          end
                                        FWT [set_index][m]=1;
                                      end
                                    dirty[set_index][m]=1;
                                  end

                                else if (cmd == 3 || cmd == 4)	// ( Invalidate command from L2 OR Snooping )

                                  begin
                                    MESI[set_index][m] = Invalid;
                                    LRU_Updated(m);
				    
                                    if(cmd == 3)
                                      begin
                                        if(dirty[set_index][m] == 1)
                                          begin
                                            if(mode == 1'b1)
                                              begin
                                                $display("------Communication with L2------");
                                                $display("Data Cache : Write to L2 <%0h>", Trace_address);
                                              end
                                            dirty[set_index][m]=0;
                                          end
                                      end
                                    if(cmd == 4)
                                      begin
                                        if(mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Return to L2 <%0h>", Trace_address);
					    $display("Data Cache : Read for Ownership from L2 <%0h>", Trace_address);
                                          end
					  data_hit = data_hit-1;
                                      end
                                    valid[set_index][m] = 0;
				
                                  end
                              end

                            //////////////////////////////--------------------EXCLUSIVE STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Exclusive)
                              begin
                                if (cmd == 0) 				// Read data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    data_read = data_read + 1;
                                    LRU_Updated(m);
                                    dirty[set_index][m]=0;
                                  end

                                else if (cmd == 1)			// Write data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modified;
                                    data_write = data_write + 1;
                                    LRU_Updated(m);
			            
                                    if (FWT [set_index][m]==0)
				    begin
                                    	FWT [set_index][m]=1;
                                    	dirty[set_index][m]=1;
				    end
                                 end

                                else if (cmd == 3 || cmd == 4)		// ( 3 - Invalidate command from L2 or snooping) )
                                  begin
                                    
                                        if(mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Return to L2 <%0h>", Trace_address);
                                            $display(" ");					    
                                          end
					  data_hit = data_hit-1;
                                      
                                    MESI[set_index][m] = Invalid;
                                    LRU_Updated(m);
				    valid[set_index][m] = 0;
                                  end
                              end

                            //////////////////////////////--------------------SHARED STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Shared)
                              begin
                                if (cmd == 0) 				// Read data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    data_read = data_read + 1;
                                    LRU_Updated(m);
                                  end

                                else if (cmd == 1)			// Write data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modified;
                                    data_write = data_write+1;
                                    LRU_Updated(m);
				     
                                    if (FWT [set_index][m]==0)
                                      begin
                                        if(mode == 1'b1)
                                          begin

                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Write to L2 <%0h>", Trace_address);
                                         
                                          end

                                        FWT [set_index][m]=1;
                                      end
                                    dirty[set_index][m]=1;
                                  end

                                else if (cmd == 3 || cmd == 4)			// ( 3 - Invalidate command from L2 or Snooping )

                                  begin
                                    if(cmd == 4)
                                      begin
                                        if(mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : <%0h>", Trace_address);
                                            $display(" ");
                                          end
                                      end
                                    MESI[set_index][m] = Invalid;
                                    LRU_Updated(m);
                                    valid[set_index][m] = 0;
                                  end
                              end
                          end  
                      end


                    ///////////////************************************ IF TAG BITS DON'T MATCH - MISS *********************************/////////////////////


                    if((valid_count < 8) && (exit == 0)) // 8ways
                      begin
                        data_miss = data_miss+1;
                        $display("-----TAG BITS DON'T MATCH - MISS-----");
                        for(int k=0; k<=7; k++)// 8ways
                          begin
                            if(exit==0 && LRU[set_index][k] == 0 && valid[set_index][k] == 0)
                              begin
                                exit = 1;

                                if(cmd == 0)
                                  begin
                                    MESI[set_index][k] = Exclusive;
                                    data_read = data_read+1;
                                    LRU_Updated(k);
				    
                                    TAG[set_index][k] = tag_index;
                                    valid[set_index][k] = 1;
                                    dirty[set_index][k] = 0;
                                    if(mode == 1'b1)
                                      begin
                                        $display("------Communication with L2------");
                                        $display("Data Cache : Read from L2 <%0h>", Trace_address);
                                      
                                      end
                                  end

                                else if(cmd == 1)
                                  begin
                                    MESI[set_index][k] = Modified;
                                    data_write=data_write+1;
                                    LRU_Updated(k);
                                    TAG[set_index][k] = tag_index;
                                    valid[set_index][k] = 1;
                                    dirty[set_index][k]=1;
                                    if (FWT [set_index][k]==0)
                                      begin
                                        if(mode == 1'b1)
                                          begin
                                            $display("--------------Communication with L2--------------");
                                            $display("Data Cache : Read for Ownership(RFO) from L2 <%0h>", Trace_address);
                                            $display("Data Cache : Write to L2 <%0h>", Trace_address);
  
                                          end
                                        FWT [set_index][k]=1;
                                      end
                                  end

                                else if(cmd == 3)
                                  begin
                                    MESI[set_index][k] = Invalid;
                                    LRU_Updated(k); 
                                    valid[set_index][k] = 0;
                                  end

                                else if(cmd == 4)
                                  begin
					if(mode == 1'b1)
                                          begin
                                   	 $display("Cache for address <%0h> is miss, hence snooping an Read for Ownership(RFO) from other processor isn't possible.", Trace_address);
                                  	end
				end
                              end
                          end
                      end

                    if((valid_count==Ways) && (exit == 0))
                      begin
                        data_miss = data_miss + 1;
                        $display("-----TAG BITS DONT MATCH - MISS-----");
                        for(int n=0; n<=7; n++) //8ways
                          begin
                            if(exit==0 && LRU [set_index][n] == 0)
                              begin
                                exit = 1;

                                if(cmd == 0)
                                  begin
                                    MESI[set_index][n] = Exclusive;
                                    data_read = data_read+1;
                                    LRU_Updated(n);
                                    TAG[set_index][n] = tag_index;
                                    valid[set_index][n] = 1;
                                    dirty[set_index][n]=0;
                                    if(mode == 1'b1)
                                      begin
                                        $display("------Communication with L2------");
                                        $display("Data Cache : Write to L2  <%0h> and Read from L2 <%0h>", Trace_address, Trace_address);
                                        
                                      end
                                  end

                                else if(cmd == 1)
                                  begin
                                    MESI[set_index][n] = Modified;
                                    data_write=data_write+1;
                                    LRU_Updated(n);
                                    TAG[set_index][n] = tag_index;
                                    valid[set_index][n] = 1;
                                    dirty[set_index][n] = 1;
                                    if(mode == 1'b1)
                                      begin
                                        $display("---------------Communication with L2---------------");
                                        $display("Data Cache : Read for Ownership(RFO) from L2 <%0h>", Trace_address);
                       
                                      end

                                    if (FWT [set_index][n]==0)
                                      begin
                                        if(mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Write to L2 <%0h>", Trace_address);
                                          end
                                        FWT [set_index][n]=1;
                                      end
                                  end

                                else if(cmd == 3)
                                  begin
                                    MESI[set_index][n] = Invalid;
                                    LRU_Updated(n); 
                                    valid[set_index][n] = 0;
                                  end

                                else if(cmd == 4)
                                    $display("Cache for address <%0h> is miss, hence snooping an Read for Ownership(RFO) from other processor isn't possible.", Trace_address);
                              end
                          end
                      end
                  end
                8:
                  begin
                    foreach (MESI [x,y])
                      begin
                        TAG[x][y] = 0;
                        MESI[x][y] = Invalid;
                        LRU[x][y] = 0;
                        FWT[x][y] = 0;
                        valid[x][y] = 0;
                        dirty[x][y] = 0;
                      end
                  end
                9:
		  begin
                    Data_Output();
                    Data_report();
                  end
              endcase
            end
        end
      exit = 0;
      valid_count = 0;
    end

  function void LRU_Updated;
    input int p;
    for( int q =0 ; q <= 7 ; q++ ) // 8ways
      begin
        if(q != p)
          begin
            if (LRU [set_index] [q] > LRU [set_index] [q])
	       LRU [set_index] [q] = LRU [set_index] [q]-1;
	  end
      end
    LRU [set_index] [p] = Ways-1;
  endfunction

  function void Data_report;
    $display("---------------DATA CACHE statistics---------------");
    $display("Total Number of data_read  = %0d", data_read);
    $display("Total Number of data_write = %0d", data_write);
    $display("Total Number of data_hit   = %0d", data_hit);
    $display("Total Number of data_miss = %0d", data_miss);
    if ( data_hit + data_miss == 0 )
      $display ("data_miss and data_hit is zero");
    else
      begin
        dhit_ratio = ( data_hit / ( data_hit + data_miss ) )*100;
        $display("DATA CACHE HIT ratio = %f", dhit_ratio);
      end
  endfunction

  function void Data_Output;
    $display("---------------Contents of DATA CACHE---------------");
    $display("TRACE ADDRESS = %0h and SET NUMBER = %0h", Trace_address, set_index);
    $display("TAG[7] = %0h | TAG[6] = %0h | TAG[5] = %0h | TAG[4] = %0h | TAG[3] = %0h | TAG[2] = %0h | TAG[1] = %0h | TAG[0] = %0h", TAG[set_index][7], TAG[set_index][6], TAG[set_index][5], TAG[set_index][4], TAG[set_index][3], TAG[set_index][2], TAG[set_index][1], TAG[set_index][0]);
    $display("LRU[7] = %0d | LRU[6] = %0d | LRU[5] = %0d | LRU[4] = %0d | LRU[3] = %0d | LRU[2] = %0d | LRU[1] = %0d | LRU[0] = %0d", LRU[set_index][7], LRU[set_index][6], LRU[set_index][5], LRU[set_index][4], LRU[set_index][3], LRU[set_index][2], LRU[set_index][1], LRU[set_index][0]);
    $display("STATE[7] = %0d | STATE[6] = %0d | STATE[5] = %0d | STATE[4] = %0d | STATE[3] = %0d | STATE[2] = %0d | STATE[1] = %0d | STATE[0] = %0d" ,MESI[set_index][7].name, MESI[set_index][6].name, MESI[set_index][5].name, MESI[set_index][4].name, MESI[set_index][3].name, MESI[set_index][2].name, MESI[set_index][1].name, MESI[set_index][0].name);
    $display("DIRTY[7] = %0d | DIRTY[6] = %0d | DIRTY[5] = %0d | DIRTY[4] = %0d | DIRTY[3] = %0d | DIRTY[2] = %0d | DIRTY[1] = %0d | DIRTY[0] = %0d", dirty[set_index][7], dirty[set_index][6], dirty[set_index][5], dirty[set_index][4], dirty[set_index][3], dirty[set_index][2], dirty[set_index][1], dirty[set_index][0]);
    $display("VALID[7] = %0d | VALID[6] = %0d | VALID[5] = %0d | VALID[4] = %0d | VALID[3] = %0d | VALID[2] = %0d | VALID[1] = %0d | VALID[0] = %0d", valid[set_index][7], valid[set_index][6], valid[set_index][5], valid[set_index][4], valid[set_index][3], valid[set_index][2], valid[set_index][1], valid[set_index][0]);
  endfunction
endmodule








 

