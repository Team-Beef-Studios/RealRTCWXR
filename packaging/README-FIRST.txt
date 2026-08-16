RealRTCW XR
===========

WHAT THIS IS
------------
RealRTCW XR is a VR port of RealRTCW, a community overhaul of Return to Castle
Wolfenstein. It runs on OpenXR headsets.


TWO INSTALLERS
--------------
Minimal   Ships the VR build only. You supply the RealRTCW data and the Return
          to Castle Wolfenstein data.

Full      Also ships the RealRTCW data, with the permission of the RealRTCW
          author. You supply only the Return to Castle Wolfenstein data.

The file name tells you which one you have.


WHAT YOU NEED
-------------
1. Return to Castle Wolfenstein. Both installers need its data files.
2. RealRTCW, set to a 5.0 beta branch. The Full installer does not need this.
3. An OpenXR runtime, for example the Meta Quest Link app or SteamVR.


HOW TO INSTALL
--------------
1. Run RealRTCWXR-<version>-<bundle>-Setup.exe.
2. Choose the install folder.
3. Choose where the game data comes from:

     "Copy the game data from my Steam installation"
         The setup finds your Steam libraries and copies the files. Both games
         must already be installed through Steam.

     "I will provide the game files myself"
         Use this if you own the games on GOG, on disc, or anywhere other than
         Steam. The setup lists the exact files it needs and names the folder to
         copy them into. Copy the files, then press Install again.

4. Tick or clear "Put a RealRTCW XR shortcut on my desktop". It is ticked by
   default. The setup makes the shortcut only if the install succeeds.
5. Press Install.

The setup never changes your Steam copies. It only reads them.

To remove the shortcut later, delete "RealRTCW XR" from your desktop.


HOW TO SET THE REALRTCW BETA BRANCH
-----------------------------------
The Steam route checks this. The Full installer does not need it.

1. Open the Steam library.
2. Right-click RealRTCW, then choose Properties.
3. Open the Betas tab.
4. Choose the 5.0 beta from the list.
5. Let Steam finish the update.


IF SOMETHING GOES WRONG
-----------------------
Run the setup again. It only copies files that changed.

To repair an install without unpacking again, open PowerShell in the install
folder and run:

    powershell -ExecutionPolicy Bypass -File Setup-RealRTCWXR.ps1

The setup script accepts these switches:

    -InstallRoot <path>   Use a different install folder.
    -ManualData           Do not use Steam. List the files you must copy in.
    -SkipVersionCheck     Continue even if RealRTCW is not on a 5.0 beta branch.
    -CreateShortcut       Put a shortcut on the desktop.

The setup exe accepts these switches:

    /D=<path>     Install into <path>.
    /S            Install without the window.
    /MANUAL       Do not use Steam.
    /NOSHORTCUT   Do not make a desktop shortcut.
    /FORCE        Pass -SkipVersionCheck to the setup script.


LICENCE
-------
See COPYING.txt. RealRTCW XR is built on the iortcw and RealRTCW source code,
released under the GNU General Public License version 3.
