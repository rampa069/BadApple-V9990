# Bad Apple!! for MSX turbo R + V9990 + MoonSound

The "Bad Apple!!" shadow-art video, full length (3:39) at 30 fps on the
Yamaha V9990 (GFX9000), with its music and its vocals on the wave part of
the Yamaha OPL4 (MoonSound), streamed from mass storage under Nextor.

The demo was written to test the SDRAM transfers of the turbo R core of
[ZEMMIX](https://github.com/BigMist/ZEMMIX): there the VRAM of the V9990
(through its cache) and the wave memory of the OPL4 both live in SDRAM (the
second SDRAM on the SiDi128), while Nextor reads the stream from the SD card
and the R800 sends it to the V9990 and to the OPL4.  It runs on the ZEMMIX
turbo R core and in [openMSX](https://openmsx.org/).

Video: <https://youtu.be/JJknUYltgDg>

## Features

**Video**

* V9990 B1 mode, 256x212, 2 bits per pixel: 4 grays (palette 0, 10, 21, 31),
  so the edges of the shadows are anti-aliased.
* 30 frames per second, 6572 frames, synchronized with the 60 Hz interrupt.
* Every frame is the list of runs of VRAM bytes that changed since the frame
  before (359 runs and 1.6 KB in a typical frame, 913 runs at worst).
* The stream is read ahead into a ring of 16 KB mapper segments, so the
  storage only has to deliver the average rate, about 56 KB/s.

**Audio, OPL4 wave part only (FM not used)**

* 12 of the 24 wave channels: 10 for the music, 2 (in turn) for the voice.
* The music is the XM arrangement by Torvald, played by a FastTracker 2
  engine at conversion time and turned into OPL4 register writes: 102,917
  writes over 13,159 ticks of 60 Hz, carried inside the video stream a few
  frames ahead and written by an interrupt routine (H.TIMI).
* The vocals of nomico, separated from the original PV, are 37 wave pieces
  of up to 4 seconds, 8 bit at 16 kHz, started on the 60 Hz grid; the part
  that repeats in the song is stored once.
* The XM is retimed from 137 to 138 BPM, the tempo of the PV, so that music,
  vocals and video stay together (within about 10 ms) for the whole song.
* 54 wave tones, 1856 KB of sample RAM.

## Requirements

* MSX turbo R: the R800 is needed for 30 fps (on a Z80 the heaviest frames
  only reach about 15 fps).
* V9990 (GFX9000 or compatible) at I/O ports 60h-6Fh.
* MoonSound (OPL4) with **2 MB of sample RAM**.  Without a MoonSound the
  video plays alone; smaller sample RAM sizes are not supported.
* MSX-DOS 2 / Nextor; a memory mapper with at least 2 free segments (the
  player uses up to 32, 512 KB, as read-ahead buffer) and a TPA up to
  CC00h or over (the music FIFO and interrupt routine live in page 3).
* Mass storage (SD, IDE...) with 14.5 MB for the files, about 56 KB/s.

## Running

Copy `BADAPPLE.COM`, `BADAPPLE.V99` and `BADAPPLE.OPL` to a directory and
run `BADAPPLE` from there.  The player first loads `BADAPPLE.OPL` into the
OPL4 (one dot per 16 KB), then plays.  At the end it prints the number of
late frames and of buffer underruns (0 and 0 when all goes well) and turns
the V9990 display off, so that a video mixer that follows the V9990 display
(the *Auto* option of ZEMMIX) goes back to the V9958.

## openMSX

Tested with openMSX 21.0: a turbo R machine, the `gfx9000` extension, a
MoonSound with 2 MB of sample RAM and Nextor on a storage extension (for
instance a MegaFlashROM SCC+ SD or a Sunrise IDE) holding the three files.
The `moonsound` extension of openMSX has 640 KB of sample RAM; for 2 MB use
a copy of it with:

```xml
<sampleram>2048</sampleram>
```

To see the output of the V9990: `set videosource GFX9000` in the console.

## Files

| File | Size | Contents |
|---|---|---|
| `BADAPPLE.COM` | 2.6 KB | the player, MSX-DOS 2 |
| `BADAPPLE.V99` | 12.0 MB | video and music events |
| `BADAPPLE.OPL` | 1.9 MB | image of the OPL4 sample RAM |
| `badapple.asm` | | source of the player (`pasmo badapple.asm BADAPPLE.COM`) |

### BADAPPLE.V99 (version 3)

A 512 byte header (`BA99`, version, mode, frame count, palette...), then
16 KB chunks of frame records; no record crosses a chunk and a length word
of 0 ends the records of a chunk.  A frame record:

```
word  length of what follows
runs: word  bits 13-0 VRAM address, bits 15-14 length 1-3 (0: a length
            byte follows, 1-256), then the bytes
word  FFFFh
byte  music ticks T, then T times: byte n, n pairs (OPL4 wave register, value)
```

### BADAPPLE.OPL (version 1)

`OPL4`, version, 3 bytes 0, the image size (4 bytes) and its address in the
OPL4 memory (4 bytes, 200000h), then the image: the 128 headers of 12
bytes of the wave tones 384-511, then the waves.

## Credits and thanks

* **ZUN** (Team Shanghai Alice): "Bad Apple!!", from *Touhou Gensokyo ~
  Lotus Land Story*.
* **Alstroemeria Records**: the arrangement "Bad Apple!! feat. nomico",
  sung by **nomico**.
* **Anira** (あにら): the shadow-art PV.
* **Torvald**: the XM "Bad Apple!! ft. nomico" (2016,
  [The Mod Archive #178526](https://modarchive.org/index.php?request=view_by_moduleid&query=178526)),
  the music of this demo.
* **Demucs** (Meta AI): the separation of the vocals.
* **Yamaha**: the YMF278B datasheet and application manual, found on
  **Grauw**'s [MSX Assembly Page](https://map.grauw.nl/).
* **Patriek Lesparre**: the transcription of the V9990 programmer's manual
  on MSX Banzai.
* **MoltSXalats**: the article on programming the OPL4 wave part.
* **The openMSX team**: the emulator where all of it was tested first.
* **Konamiman**: Nextor.  **Manuel Pazos**: the MegaFlashROM SCC+ SD driver.
* **srg320** (YMF278B) and **Greg Taylor** (opl3_fpga): the OPL4 / OPL3 of
  the ZEMMIX core.
* The **libopenmpt** and **librosa** projects: reference rendering of the
  XM and the alignment of the XM with the PV.
* The Bad Apple ports that showed the way: **Ryun** and **Sharksym** (MSX),
  **Eric Lafortune** (TI-99/4A), **Bitshifters** (BBC Micro).

## License

The player (`badapple.asm`, `BADAPPLE.COM`) is under the MIT license, see
[LICENSE](LICENSE).  The data files `BADAPPLE.V99` and `BADAPPLE.OPL` are
derived from the works credited above (the PV, the song and its vocals, the
XM), which remain the property of their authors; they are not covered by the
MIT license.

Demo and core: <https://github.com/rampa069/BadApple-V9990>,
<https://github.com/BigMist/ZEMMIX>.  Video: <https://youtu.be/JJknUYltgDg>.
