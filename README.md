# Whiteboard Source for OBS

This script adds a whiteboard source type to OBS that allows users to annotate their stream/recording while live.

This is a fork of [Mike Welsh](https://github.com/Herschel/)'s original script with some fixes and new features (drawing arrows, undo, and more).

*Note*: Currently only supports Windows.

## How to Use

1. Download the latest version of this script and extract the zip file wherever you like.
2. Go to Tools > Scripts in OBS, then click the + button at the bottom of your list of scripts.
3. Select the `main.lua` file in the directory you extracted earlier to add it as a script.
4. In the main OBS window, click the + button below your list of sources and then select "Whiteboard". *(Note: you may have to toggle the visibility of the whiteboard on/off once to activate it)*
5. In the main OBS window, right click your scene and select "Windowed Projector".
6. Draw on the projector window by left clicking

The following keys can be used while the projector window is focused:
- `1-9`: select brush color
- `0`: select eraser
- `+` or `-`: increase or decrease the size of your brush/eraser
- `e`: toggle between brush and eraser
- `a`: toggle brush to or from arrow mode
- backspace: undo previous change
- `c`: clear whiteboard (this cannot be undone)

## Known issues

- Keyboard shortcuts are currently not configurable.
- The script can crash if reloaded while active. That is, by clicking the "refresh" button in the Tools > Scripts window.
  * This is due to a bug in OBS that only occurs with scripts that define their own source types. In certain situations, a deadlock can occur between the UI thread and the rendering thread.
- Whiteboard source doesn't accept inputs after being added to a scene, or after the script is refreshed.
  * This is because the source is only interactable when it's active. There's unfortunately no way to check whether a source is currently active, so we rely on the triggers on transition between active and deactive to determine when to enable interaction. Certain situations do not trigger this transition (e.g. adding a new source, refreshing the script, etc.), hence the source never knows it's active.


## Authors

- **mwelsh** *([TILT forums](http://tiltforums.com/u/mwelsh))*  *([GitHub](https://github.com/Herschel/obs-whiteboard))*  
- **Tari**  
- **Joseph Mansfield** *([GitHub](https://github.com/sftrabbit))* *([YouTube](https://youtube.com/@JoePlaysPuzzleGames))* *([josephmansfield.uk](https://josephmansfield.uk))*

