#!/usr/bin/env python3.7

import iterm2

# This script was created with the "basic" environment which does not
# support adding dependencies with pip.


async def stack_windows_down(
    windows, x, init_y, default_height, flush_right=False
):
    last_y = init_y
    for window in windows:
        if window is not None:
            frame = await window.async_get_frame()
            if flush_right:
                # In this case, x is actually the max X value.
                frame.origin.x = x - frame.size.width
            else:
                frame.origin.x = x
            frame.origin.y = last_y - frame.size.height
            await window.async_set_frame(frame)
            print(frame.origin)
            last_y = frame.origin.y
        else:
            last_y = last_y - default_height
        # I like one pixel of extra spacing.
        last_y -= 1


async def main(connection):
    app = await iterm2.async_get_app(connection)
    first_eight_windows = [None] * 8
    for window in app.terminal_windows:
        idx = window._Window__number
        if idx < len(first_eight_windows):
            first_eight_windows[idx] = window

    default_width = None
    default_height = None
    for window in first_eight_windows:
        if window is None:
            continue
        for session in window.current_tab.sessions:
            session.preferred_size.height = 24
            session.preferred_size.width = 80
        await window.current_tab.async_update_layout()
        frame = await window.async_get_frame()
        default_width = min(default_width or frame.size.width, frame.size.width)
        default_height = min(
            default_height or frame.size.height, frame.size.height
        )
    print("def WxH", default_width, default_height)

    # Let's do stupid stunts to find the screen dimensions.  This is
    # fucking stupid.  This will all break with >1 monitor.  In that
    # case I think I'd end up importing PyObjC and doing some calls to
    # get the "primary" display or something.
    a_window = next(w for w in first_eight_windows if w)
    frame = await a_window.async_get_frame()
    frame.origin.x = -99999
    frame.origin.y = 99999
    await a_window.async_set_frame(frame)
    frame = await a_window.async_get_frame()
    max_y = frame.origin.y + frame.size.height
    # So now the bottom left of the window is way off the left size of
    # the screen, and the bottom is showing us the maximum bottom left
    # Y coordinate.  In my experience, the difference between the
    # window width and the most negative allowed (allowed by iTerm, at
    # least) X coordinate is the same offset between the right edge of
    # the screen and the most positive X coordinate iTerm will allow.
    #
    # Read a bit more, it might make sense.
    assert frame.origin.x < 0
    min_x_visible = frame.size.width + frame.origin.x
    # Now move the window as far as it will go to the right and we can
    # use that to derive our display width.
    frame.origin.x = 99999
    await a_window.async_set_frame(frame)
    frame = await a_window.async_get_frame()
    max_x = frame.origin.x + min_x_visible
    print("duck1", frame.origin.x, min_x_visible)
    print("max x,y", max_x, max_y)

    await stack_windows_down(first_eight_windows[:3], 0, max_y, default_height)
    await stack_windows_down(
        first_eight_windows[3:6], max_x, max_y, default_height, flush_right=True
    )
    await stack_windows_down(
        first_eight_windows[6:],
        int(default_width * 0.8),
        int(max_y - 0.5 * default_height),
        default_height,
    )


iterm2.run_until_complete(main)
