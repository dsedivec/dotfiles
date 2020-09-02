#!/usr/bin/env python
import sys

import iterm2


async def main(connection):
    color_preset_name = sys.argv[1]
    color_preset = await iterm2.ColorPreset.async_get(
        connection, color_preset_name
    )
    # Update the list of all profiles and iterate over them.
    profiles = await iterm2.PartialProfile.async_query(connection)
    for partial in profiles:
        # Fetch the full profile and then set the color preset in it.
        profile = await partial.async_get_full_profile()
        await profile.async_set_color_preset(color_preset)


# Passing True for the second parameter means keep trying to
# connect until the app launches.
iterm2.run_until_complete(main, True)
