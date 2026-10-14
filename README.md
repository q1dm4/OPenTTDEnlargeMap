# OpenTTD Save Map Utility — Windows 64-bit test release 0.1

## Install and run

1. Extract this ZIP **into the existing `Sadingham-Population` folder** from the population v0.2 Windows package. `Launch-Map-Utility.bat`, both PowerShell files, `save-inspect.exe`, and the patched `openttd.exe` must be beside one another. This download is a small add-on; it does not include another copy of the engine.
2. Keep the original NewGRF TAR files in that folder's `newgrf` directory, as before. The utility uses that engine's base graphics and language files.
3. Double-click **Launch-Map-Utility.bat**. No Python installation is required; the launcher uses Windows PowerShell 5.1 and Windows Forms.
4. Click **Choose save**, select your `.sav`, and review the actual map dimensions and population counts.
5. Select **double both dimensions**, **double width only**, or **double height only**. The launcher shows added tiles and approximate raw map tile memory, excluding other engine memory.
6. Keep the population checkbox selected to add towns and industries in the new area, or uncheck it for empty land. Suggested counts match the existing density, capped at the engine's 2,000 added towns and 10,000 added industries. You can change these counts.
7. Click **Create enlarged save**, choose a new output filename, and wait for the result. Load that output in your compatible JGRPP game to test it.

Your original save is opened read-only and copied into a private job folder. The engine expands the job copy, optionally reloads and populates the new land, then the utility verifies the output dimensions and writes the chosen output using atomic overwrite protection. An existing output filename is refused. Cancelling a job does not publish its output.

The launcher verifies the hash of the population v0.2 patched executable. It refuses stock OpenTTD or a different build; use the executable from that specific package. A new engine release will require a matching launcher update.

## Supported saves and limits

This first release targets modern OpenTTD/JGRPP save chunk layouts compatible with the supplied JGRPP 0.73.0 engine. The reader supports **zlib, LZMA/XZ, and uncompressed** wrappers. Zstandard, legacy LZO, unsupported chunk layouts, and files above the reader's 512 MiB compressed/decompressed limits are refused. For another compression format, use compatible JGRPP to save a separate zlib copy first.

Proposed map sizes are limited to **16,777,216 total tiles** (equivalent to 4096×4096), even though the engine supports larger maps. Larger maps consume additional memory beyond the displayed tile data.

The patched engine performs its existing compatibility checks. Expansion rejects active AI/GameScript state and active disaster vehicles; population rejects AI/GameScript saves. Missing NewGRFs or an unsupported save may prevent a job from completing. The utility does not download NewGRFs or automatically acknowledge compatibility warnings.

Added terrain stays flat. Population keeps normal industry placement rules, so actual counts can be lower than requested. Initial generation protects the original area and leaves its safety strip; normal later gameplay can subsequently develop land. This utility introduces no new teleportation behavior.

## Results and logs

The result dialog shows the final dimensions and total town/industry counts. When population is selected it also shows the actual additions reported by the engine. **Open output folder** selects the new save in Explorer.

Job folders are retained under `%LOCALAPPDATA%\OpenTTD-Map-Utility\jobs`. They contain the input copy, request, generated engine scripts, console logs and intermediate saves. They can be deleted after you have checked your final output. The utility times out a child process after five minutes; it leaves your original save untouched and does not publish a failed job.

## Testing status

The read-only parser was tested against the delivered Sadingham population save: **2048×2048, 1,352 towns, 6,401 industries**, in zlib, LZMA and uncompressed forms. Spaced and Unicode filenames, corrupt/truncated input, unsupported formats, rectangular proposals, count caps, generated console scripts, output publication and overwrite guards were tested. PowerShell functions ran under PowerShell 7.4.6 on Linux, and both scripts passed PowerShell's parser. The native Windows reader compiled as x64 and imports only Windows system/UCRT DLLs.

The v0.2 engine's expansion/population commands were verified earlier. **The new Windows graphical launcher and its complete Windows engine workflow still need your Windows test.** A short engine simulation does not establish long-term save stability.

## Source

`source/save_inspect.cpp` is the complete reader source. Static zlib and xz/liblzma source archives and notices are included. Build the reader with C++20, linking zlib and liblzma; Windows builds use the LLVM MinGW UCRT x86_64 toolchain, `-static -municode`, and a console subsystem.

`source/engine-population-complete.patch` corrects the prior engine source bundle, whose patch omitted the population additions. Apply this complete patch **instead of** the old `engine.patch` to the official JGRPP 0.73.0 base source archive already included in the v0.2 package. It includes the gateway prototype, expansion exporter and population implementation. The engine executable is unchanged by this launcher add-on.

The scripts and reader use GPL-2.0-only; see LICENSE.md and dependency notices. Verification scripts are provided for developers and are not needed to use the launcher. `Expand-Save.ps1 -SelfTest` runs basic launcher checks without opening the GUI; `-Inspect <save-path>` prints the reader's JSON metadata.
