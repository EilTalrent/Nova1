------------------------------------------------------------------------------
--  Nova.Crash : the NOVA-1 crash screen.
--
--  The zero-footprint runtime has no exception propagation, so when any Ada
--  check fails (range, overflow, index, division by zero, a failed
--  precondition...) the compiler calls this handler with the source file and
--  line. It paints a crash screen, reports to the debug port and powers off.
--  Range errors become a red screen instead of silent memory corruption.
------------------------------------------------------------------------------

with System;

package Nova.Crash is

   Crash_Exit_Code : constant := 16#AD_A0#;

   procedure Last_Chance_Handler (Source_Location : System.Address; Line : Integer)
     with Export, Convention => C, External_Name => "__gnat_last_chance_handler",
          No_Return;

end Nova.Crash;
