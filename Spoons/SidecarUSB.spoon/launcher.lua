-- Running sidecarctl, the command line tool that starts and ends Sidecar. Hammerspoon
-- has no Sidecar API, so the Spoon runs it as a separate process and reads its exit
-- code and output.
--
-- Exit codes: 0 done, 1 bad arguments, 2 no reachable devices, or no Sidecar display
-- for a boost, 3 no such device, 4 a SidecarCore or CoreGraphics error, 5 SidecarCore
-- missing, 6 no device given and more than one reachable, 7 a boost already running,
-- 8 the connection asked for is unavailable, 9 the device reports it is not ready.

local M = {}

-- hs.task takes a full path, and Hammerspoon does not have the shell's PATH to
-- search, so the path is checked as given
function M.find(path)
  if path and hs.fs.attributes(path, "mode") == "file" then return path end
  return nil
end

-- Runs it with args and calls done(exitCode, output) on the main thread. The task is
-- returned so the caller can hold it, since an unreferenced task can be collected
-- before it finishes, and terminate it.
function M.run(path, args, done)
  local task = hs.task.new(path, function(code, out, err)
    done(code, (out or "") .. (err or ""))
  end, args)
  task:start()
  return task
end

return M
