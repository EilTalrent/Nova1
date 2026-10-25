------------------------------------------------------------------------------
--  NOVA-1 zero-footprint runtime : System.Assertions
--  A failed Pre/Post/Assert lands in __gnat_last_chance_handler.
------------------------------------------------------------------------------

package System.Assertions is
   pragma Preelaborate;

   Assert_Failure : exception;

   procedure Raise_Assert_Failure (Msg : String) with No_Return;

end System.Assertions;
