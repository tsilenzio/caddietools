-- Scroll event properties and the mark on events a glide posts, shared by the
-- direction flip and the glide

local props = hs.eventtap.event.properties

return {
  CONTINUOUS = props.scrollWheelEventIsContinuous,
  DELTA = props.scrollWheelEventDeltaAxis1,
  POINT = props.scrollWheelEventPointDeltaAxis1,
  FIXED = props.scrollWheelEventFixedPtDeltaAxis1,
  DELTA_X = props.scrollWheelEventDeltaAxis2,
  POINT_X = props.scrollWheelEventPointDeltaAxis2,
  USER_DATA = props.eventSourceUserData,
  TARGET_PID = props.eventTargetUnixProcessID,
  -- Tags the events a glide posts, "HSSMOOTH" in ASCII. They pass back through this
  -- Spoon's own tap, which must let them go untouched.
  GLIDE_MARK = 0x4853534D4F4F5448,
}
