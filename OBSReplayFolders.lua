obs = obslua
ffi = require("ffi")

-- load the shared object (detect_game.so)
ffi.cdef[[
    int get_running_game_path(char* buffer, int bufferSize);
]]

-- load the detect_game.so file (make sure its in the same directory as the lua script or specify the correct path)
detect_game = ffi.load(script_path() .. "detect_game.so")

sound_path = ""

-- description in obs
function script_description()
	 return [[Saves replays to sub-folders using the current fullscreen/focused video game executable name on Linux.

        Author: redraskal
            (original)
        Modified by: siucrae
            (adapted for linux with .so)
    ]]
end

function script_update(settings)
	sound_path = obs.obs_data_get_string(settings, "sound_path")
end

function script_properties()
local props = obs.obs_properties_create()
obs.obs_properties_add_path(
	props, "sound_path", "Save Complete Sound",
	obs.OBS_PATH_FILE, "Audio Files (*.wav *.ogg *.mp3)", nil
)
return props
end

-- add a callback for frontend events in OBS (when a replay buffer is saved)
function script_load()
    obs.obs_frontend_add_event_callback(obs_frontend_callback)
end

-- callback to process events triggered by obs
function obs_frontend_callback(event)
	if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED then
		local path = get_replay_buffer_output()			-- get the path to the replay buffer output
		local folder = get_running_game_title()			-- get the game title from the shared object (detect_game.so)
		if path ~= nil and folder ~= nil then			-- if both the replay path and folder/game title are valid then move the file
			print("Moving " .. path .. " to " .. folder)	-- move the replay file to the appropriate folder
			move(path, folder)
			if sound_path ~= "" then
				os.execute(string.format("paplay '%s' 2>/dev/null &", sound_path))
			end
		end
	end
end

-- retrieve the path of the latest replay buffer saved in obs
function get_replay_buffer_output()
	local replay_buffer = obs.obs_frontend_get_replay_buffer_output()	-- get the replay buffer object
	local cd = obs.calldata_create()					-- create an empty calldata object for passing data
	local ph = obs.obs_output_get_proc_handler(replay_buffer)		-- get the process handler for the replay buffer
	obs.proc_handler_call(ph, "get_last_replay", cd)			-- call the process handler to get the last saved replay
	local path = obs.calldata_string(cd, "path")				-- retrieve the path of the replay from calldata
	obs.calldata_destroy(cd)						-- clean up the calldata object
	obs.obs_output_release(replay_buffer)					-- release the replay buffer
	return path
end

-- function to get the running games title using the shared object (detect_game.so)
function get_running_game_title()
  local buf   = ffi.new("char[?]", 260)
  local ok    = detect_game.get_running_game_path(buf, 260)
  if ok ~= 0 then
    return nil
  end

  local title = ffi.string(buf)
  title = title:gsub("[\r\n]+", "")

  if #title == 0 then
    return nil
  end

  return title
end

-- function to move the replay file to a new folder based on the game title
function move(path, folder)
	local sep = string.match(path, "^.*()/")			-- extract the directory separator from the file path
	local root = string.sub(path, 1, sep) .. folder			-- construct the new root directory for the game folder
	local file_name = string.sub(path, sep, string.len(path))	-- get the file name from the original path
	file_name = file_name:gsub("Replay", folder)
	local adjusted_path = root .. file_name				-- construct the new file path with the folder
	
	-- check if the target directory exists; if not then create it
		if obs.os_file_exists(root) == false then
			obs.os_mkdir(root)
		end

	-- rename/move the file to the new location
	obs.os_rename(path, adjusted_path)
end
