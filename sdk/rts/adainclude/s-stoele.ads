------------------------------------------------------------------------------
--  NOVA-1 zero-footprint runtime : System.Storage_Elements
------------------------------------------------------------------------------

package System.Storage_Elements is
   pragma Pure;
   pragma No_Elaboration_Code_All;

   type Storage_Offset is range -(2 ** 31) .. 2 ** 31 - 1;
   subtype Storage_Count is Storage_Offset range 0 .. Storage_Offset'Last;

   type Storage_Element is mod 2 ** Storage_Unit;
   for Storage_Element'Size use Storage_Unit;

   type Storage_Array is
     array (Storage_Offset range <>) of aliased Storage_Element;
   for Storage_Array'Component_Size use Storage_Unit;

   type Integer_Address is mod Memory_Size;

   function "+" (Left : Address; Right : Storage_Offset) return Address
     with Inline_Always;
   function "+" (Left : Storage_Offset; Right : Address) return Address
     with Inline_Always;
   function "-" (Left : Address; Right : Storage_Offset) return Address
     with Inline_Always;
   function "-" (Left, Right : Address) return Storage_Offset
     with Inline_Always;

   function To_Address (Value : Integer_Address) return Address
     with Inline_Always;
   function To_Integer (Value : Address) return Integer_Address
     with Inline_Always;

end System.Storage_Elements;
