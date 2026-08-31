module KuiperTemplate.Increment

#lang-pulse

open Kuiper
module U64 = FStar.UInt64

(* A minimal verified GPU kernel and synchronous host wrapper. Replace this
   module with the concrete entry points for your package. *)
inline_for_extraction noextract
fn increment_kernel (output : gpu_ref u64) (#initial : erased u64)
  preserves gpu
  requires output |-> initial
  ensures output |-> U64.add_mod initial 1uL
{
  let value = gpu_read output;
  gpu_write output (U64.add_mod value 1uL);
}

fn run (_ : unit)
  preserves cpu
  requires emp
  returns value : u64
  ensures emp
{
  let mut host_value = 41uL;
  let device_value = gpu_alloc0 #u64 ();

  Kuiper.Ref.gpu_memcpy_host_to_device device_value host_value;
  with initial. assert on gpu_loc (device_value |-> initial);
  launch_kernel_1
    (fun _ -> increment_kernel device_value #initial);
  Kuiper.Ref.gpu_memcpy_device_to_host host_value device_value;

  let value = !host_value;
  assert (pure (value == 42uL));
  gpu_free device_value;
  value
}
