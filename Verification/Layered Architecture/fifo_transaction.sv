// =============================================================================
// fifo_transaction.sv
//
// The single item type that flows through the testbench layers. No
// randomization yet (Step 3 of the plan is plumbing-only) -- fields are set
// directly by directed sequence code. The `rand` keywords are left in place
// because the class shape itself shouldn't need to change when
// randomization is introduced later; only the sequence that fills it in
// changes.
//
// Two transaction kinds share one class (write-side fields unused on a read
// transaction, and vice versa) rather than two separate classes, because
// the FIFO interface has no protocol coupling write and read (unlike e.g.
// APB request/response) -- a write transaction and a read transaction never
// need to refer to each other.
// =============================================================================

// Op selects which side of the FIFO a transaction drives. Declared at
// file scope (not nested inside fifo_transaction) so every call site can
// reference OP_WRITE/OP_READ directly. The original nested-typedef version
// required `fifo_transaction::OP_WRITE` at every call site outside the
// class; Vivado's XSim elaborator rejects that scope-resolved enum-literal
// form ("an enum variable may only be assigned the same enum typed
// variable or one of its values"), even though some other simulators
// accept it. Moving the enum out avoids the scope-resolution entirely.
typedef enum { OP_WRITE, OP_READ } op_e;

class fifo_transaction;

  rand op_e          op;
  rand bit [7:0]     data;       // write payload (ignored for OP_READ)
  rand int           delay_cy;   // idle cycles before this op is issued

  // Populated by the monitor when observed on the DUT pins (not by the
  // driver) -- this is the field the scoreboard actually checks against
  // its reference model.
  bit [7:0]          observed_data;
  bit                accepted;   // did the DUT actually consume/produce data
                                  // (i.e. w_en && !wfull, or r_en && !rempty)

  function new(op_e op_ = OP_WRITE, bit [7:0] data_ = 0, int delay_cy_ = 0);
    op       = op_;
    data     = data_;
    delay_cy = delay_cy_;
  endfunction

  function string to_string();
    if (op == OP_WRITE)
      return $sformatf("WRITE data=0x%0h delay=%0d", data, delay_cy);
    else
      return $sformatf("READ  delay=%0d", delay_cy);
  endfunction

endclass