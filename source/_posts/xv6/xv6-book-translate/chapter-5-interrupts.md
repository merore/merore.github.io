---
title: Chapter 5 中断和设备驱动
date: 2022-11-04 19:41:55
categories:
- xv6
- xv6-book中文翻译
---
# Chapter 5 中断和设备驱动
`驱动` 是操作系统中的一段用于管理特殊设备的代码：它配置设备的硬件，告诉设备处理工作，处理产生的中断，并与可能正在等待来自设备IO 的进程进行交互。驱动代码可能很棘手，因为驱动可能和设备并发执行。除此之外，驱动必须理解设备硬件接口，这可能会非常复杂。

需要操作系统注意的设备通常都会产生中断，这是陷阱的一种。当设备中断产生时，内核陷阱处理程序识别并调用设备中断处理程序。在 xv6 里，这种处理在 `devintr`。

许多设备驱动在两种上下文环境中执行：上半部分是进程内核线程，下半部分是中断处理。上半部分是通过一些 `read` 或 `write` 系统调用，让设备进行 IO。这些代码可能会要求硬件执行一个操作。然后代码会等待操作完成。最终设备会完成这个工作并产生一个中断。驱动的中断处理，作为下半部分，弄清楚哪个操作完成了，唤醒合适的等待线程，并告诉硬件开始等待执行下一个操作。

## Code: 控制台输入
控制台驱动（console.c）是一个简单的驱动结构。控制台驱动通过连接到 RISC-V 上的 UART 串行端口硬件，接收来自用户的输入的字符。控制台驱动每次接收一行输入，并处理特殊的输入字符，例如 `backspace` 和 `control-u`。像 shell 这样的用户进程，使用 `read` 系统调用从控制台中获取输入的行。当你在 QEMU 中向 xv6 进行输入时，你的按键会通过 QEMU 模拟的 UART 硬件传送到 xv6 中。

驱动程序进行通信交互的 UART 硬件是 QEMU 模拟的 16550 芯片。在真实的计算机上，16550 芯片会管理连接到终端和其他计算机的 RS232 串行链路。当运行 QEMU 的时候，你的键盘和显示都链接到 QEMU 上了。

UART 硬件在软件中表现为一组内存映射的控制寄存器。因为这些物理地址是 RISC-V 的硬件连接到的 UART 设备，所以 loads 和 stores 是在和设备硬件通信而不是 RAM。UART 映射地址起始于 0x10000000，即 `UART0`。UART0 有许多的控制寄存器，每个都是一个字节。它们相对于 UART0 的偏移定义在 `kernel/uart.c 中`。例如，`LSP` 寄存器包含的位表明输入的字符是否有软件正在等待读取输入的字符。这些字符可能通过 `RHR` 寄存器读取。每读一次，UART 硬件都会从内部的 FIFO 删除，并在 FIFO 为空时，清楚掉 `LSR` 上的 `read` 标志。UART 发送硬件在很大程度上独立于接受设备，如果软件写了一个字符到 THR，UART 会发送这个字节。

xv6 的 `main` 函数调用 `consoleinit` 来初始化 UART 硬件。这个代码配置每当 UART 收到输入的字符时，产生一个接受中断，并在每次 UART 发送时产生一个发送完成的中断。

xv6 的 shell 通过 `init.c` 打开的文件描述符从控制台读取。调用 `read` 系统调用到达`consoleread`。`consoleread` 等待输入到达并缓存在 cons.buf 中，拷贝输入到用户空间，最后返回用户进程。如果用户没有输入完一整行，任何正在读取的程序都会在 sleep 系统调用中等待。

当用户输入一个字符时，UART 硬件会让 RISC-V 产生一个中断，激活 xv6 的陷阱处理。陷阱处理调用 `devintr`，这个函数会查看 RISC-V 的 `scause` 寄存器以识别这个中断来自外部设备。然后它请求硬件调用 PLIC 来告诉它是那个设备中断。如果是 UART，`devintr` 会调用 `uartintr` 进行处理。

`uartintr` 从 UART 硬件中读取一个字符，并交给 `consoleintr`。`uartintr` 并不等待输入，因为后续的输入会产生新的中断。`consoleintr` 的工作是在 `cons.buf` 中收集输入的字符指导整行到达。`consoleintr` 会对特殊的字符做特殊处理。当新的一行到达的时候，`consoleintr` 打开一个 唤醒一个等待的 `consoleread`。

被唤醒之后，`consoleread` 会发现 `cons.buf` 中一整行的内容，将它拷贝到用户空间并返回。

## Code: 控制台输出
一个作用于控制台文件描述符的`write` 系统调用最终会走到 `uartputc`。设备驱动会为执行写入的进程维护一个输出缓冲区，这样就不需要等待 UART 完成输出。相反，`uartputc`  将每个字符缓存到缓冲区中，调用 `uartstart` 以启动设备传输并返回。`uartputc` 唯一会等待的情况是缓冲区已满。

UART 每次完成发送一个字节时，都会产生一个中断。`uartintr` 调用 `uartstart`，`uartstart` 会检查设备是不是真的完成了发送动作，并把下一个缓冲区中准备输出的字符交给设备。因此，如果一个进程向控制台写入多个字节，通常第一个字节是由 `uartputc` 调用的 `uartstart` 发送，剩下的字节是因为发送完成的中断`uartintr`调用 `uartstart` 来发送的。

 要注意的是，这里通过缓冲区和中断，将设备活动和进程活动进行了解耦。控制台驱动在没有进程等待读取的时候也能处理输入，后续的读取能看到这些输入。同样的，进程能够直接发送输出而不需要等待设备。这个解耦能允许进程和设备IO并发执行以提升性能，这在设备很慢或者需要立即回显的时候尤其重要。这个想法有时也被称为并行IO。

## 驱动程序中的并发
你可能注意到在 `consoleread` 和 `consoleintr` 中调用了 `acquire`。这会持有一个锁，它保护并发访问的情况下控制台驱动的数据结构。这里有三个并发的威胁：两个不同 CPU 的进程同时调用 `consoleread`；当 CPU 在 `consoleread` 中执行时，硬件可能要求 CPU 发送一个控制台中断；当正在执行 `consoleread` 时，硬件可能在其他 CPu 上产生一个控制台中断。第六章将探讨锁在这些场景下的应用。

驱动中还需要关心的另一种并发情况是一个进程正在等待来自设备的输入，但是另一个进程的输入中断信号到达了。因此，中断处理不允许考虑他们中断的进程和代码。例如，一个中断处理不能安全的在当前进程页表上调用 `copyout`。中断处理程序一般只做很少的工作，例如拷贝输入数据到缓冲区，剩下的工作将交由 `top-half` 来完成。

## 时钟中断
xv6 使用时钟中断来维护它的时钟并驱动进程切换，这个模式被成为 `compute-bound`。`usertrap` 和 `kerneltrap` 调用 `yield` 来进行进程切换。时钟中断来自于每个 RISC-V CPU 的时钟硬件。xv6 将此时钟硬件编程为定期中断每个 CPU。

RISC-V 要求时钟终端产生于机器模式（m-mode）而不是 s-mod。RISC-V 的 m-mod 工作时没有页表，并使用独立的控制寄存器，所以在 m-mod 运行 xv6 内核是不实际的。所以，xv6 的时钟中断完全独立于上述的陷阱机制。

位于 `start.c` 中的代码就是在 m-mod 下执行的，在 `main` 函数之前就设置了时钟中断。这部分的工作是对 CLINT 进行编程以定时产生一个中断。并一部分是设置一块空的区域，就像 trapframe 一样，以协助时钟终端保存寄存器和 CLINT 寄存器的地址。最终，`start` 设置 `mtvec` 的值为 `timervec` 以启用时钟中断。

时钟中断可以发生在用户或内核代码执行时；即使内核在进行一些关键操作的时候，也无法关闭时钟中断。因此，时钟中断的处理程序必须保证不打乱内核代码。一个基本的策略是中断处理程序让 RISC-V 生成一个软中断然后立刻返回。RISC-V 将这个软中断以常规陷阱的机制传递给内核，并允许内核禁用这些软中断。处理由时钟中断产生的软中断代码位于 `devintr`。

m-mod 模式的时钟中断处理程序是 `timervec`。它保存很少的寄存器在 `start` 分配的空区域中，并告诉 CLINT 当产生下一个时钟中断的时候，让 RISC-V 产生一个软中断，恢复寄存器并返回。定时器中断处理程序没有 C 代码。

## Real world
xv6 允许设备中断和时钟中断用户态和内核态发生。即使在内核态的时候，时钟中断强制让一个进程进行切换。这对内核花费大量的时间做计算，而不返回用户空间的公平时间分片很有用。然而，需要考虑，如果内核被挂起，然后在其他 CPU 上恢复，这是 xv6 中一切复杂性的根源。如果设备中断和时钟中断仅仅发生在用户态的话，内核将会简单一些。

在一台计算机上全面支持所有设备是一项困难的工作，因为这会有很多设备，设备有很多特性，设备之间的协议可能很复杂。在许多操作系统上，设备驱动代码比核心内核代码还多。

UART 设备通过读取 UART 的控制寄存器一次检索一个字符。这部分被叫做 `programmed I/O`。因为软件正推动数据的移动。IO 编程是简单的，但在高频数据上会很慢。通常来说，设备需要使用 DMA （direct memory access）技术来移动大量的数据。DMA 设备直接将数据写道 RAM 中，并且从 RAM 读取数据。现代硬盘和网络设备都使用 DMA 技术。DMA 设备的驱动会在 RAM 中准备数据，并通过写一个控制寄存器来告诉硬件处理准备好的数据。

当设备在不可预计的时间需要被系统注意时（但不会经常发生），中断就显得有意义了。但是中断具有很高的 CPU 开销。因此高速设备，例如网络和硬盘控制器会使用一些特殊的手段来减少中断。一种手段是对数据进行批量处理。另一种手段是完全禁用设备中断，并周期性的主动检测设备是否需要进行处理。这种方式被称为`polling`。`polling` 在设备快速操作时是有意义的，但如果设备大多数时候都很空闲，就会浪费 CPU 轮询。一些设备会根据当前加载情况动态的切换 `polling` 还是中断。

UART 设备拷贝第一个字符到内核中，然后把数据返回用户态。这在低速数据上是有意义的，但是这样双拷贝会降低性能。一些操作系统还会使用 DMA 来直接从设备中拷贝数据到用户空间。

## 练习
1. 修改 `uart.c` 不再使用中断。你可能需要同时修改 `console.c`
2. 添加一个网卡驱动
