# p4tool

DOS performance control tool for Intel Pentium 4 / NetBurst systems

p4tool was created to explore slowdown techniques beyond traditional methods like ODCM throttling and CR0 cache disabling.

Some of these techniques degrade CPU execution without proportionally affecting external bus throughput, enabling more realistic slowdown profiles.

## Features

- Cache and memory behavior control (MTRR + IA32_MTRRdefType)
- ODCM duty cycle modulation
- Debug Store (DS) based slowdown
- Debug Store + Branch Trace Store (BTS) slowdown
- Main RAM MTRR policy control (WriteBack / WriteThrough / UnCached)

## Why this tool exists

Traditional Pentium 4 slowdown approaches have strong limitations:

- **ODCM throttling**
  - Reduces CPU throughput
  - Also reduces external BUS performance proportionally
  - Affects overall system responsiveness (including video and I/O)

- **Cache disabling (CR0)**
  - Produces inconsistent or limited effects on NetBurst
  - Not suitable for fine-grained performance tuning
    
p4tool introduces alternative techniques:

- **Debug Store (DS) based slowdown**
  - Introduces internal CPU overhead
  - Degrades execution without proportionally impacting BUS throughput

- **BTS-assisted slowdown**
  - Increases internal logging pressure on the pipeline

- **MTRR (range-based) manipulation**
  - Affects memory access behavior (data path)
  - Does not impact instruction/trace cache

- **Default memory type override (IA32_MTRRdefType)**
  - Forces global uncached behavior
  - Produces a stronger and more consistent slowdown than CR0 on NetBurst
  - Affects both data cache and trace cache / uop cache behavior
    
These mechanisms can be combined to shape system behavior in ways that better approximate older hardware characteristics.

## NetBurst behavior and design notes

On NetBurst, traditional cache control mechanisms do not behave as expected:

- **CR0 cache disabling**
  - Does not fully eliminate cache effects
  - Can be overridden by software running in DOS

- **MTRR (range-based) manipulation**
  - Affects memory access behavior (data path)
  - Does not impact trace cache / uop cache behavior

- **IA32_MTRRdefType (default memory type)**
  - Forces global uncached behavior
  - Affects both data cache and trace cache / uop cache behavior
  - Produces a stronger and more consistent slowdown than CR0

For this reason, p4tool does not rely on CR0-based cache control.

Some DOS programs (e.g. Ultima VII) modify CR0 at runtime, which can re-enable cache and break external performance control.

Using IA32_MTRRdefType instead provides stable, system-wide slowdown behavior that is not affected by legacy software.

These architectural characteristics enable p4tool to reach performance profiles not achievable with traditional methods.

## Build

Assemble with NASM:
nasm -f bin src/p4tool.asm -o p4tool.com
