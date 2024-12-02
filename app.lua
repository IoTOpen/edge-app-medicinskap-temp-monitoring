statusTopic = 'obj/app/' .. app.id .. '/status'
statusInterval = 300

local function matchCriteria(fn, criteria)
    local isArray = false
    local arrayMatch = false
    for k, v in pairs(criteria) do
        if math.type(k) ~= nil then
            isArray = true
            if fn.id == v then
                arrayMatch = true
                break
            end
        else
            if k == 'id' then
                if fn.id ~= v then return false end
            end
            if k == 'type' then
                if fn.type:match('^' .. v .. '$') == nil then return false end
            end
            if fn.meta[k] == nil then return false end
            if (fn.meta[k]:match('^' .. v .. '$') == nil) then return false end
        end
    end
    if isArray then return arrayMatch end
    return true
end

function findDevice(criteria)
    devices = lynx.getDevices()
    if math.type(criteria) ~= nil then
        for _, dev in ipairs(devices) do
            if dev.id == criteria then return dev end
        end
    elseif type(criteria) == 'table' then
        for _, dev in ipairs(devices) do
            if matchCriteria(dev, criteria) then return dev end
        end
    end
    return nil
end

function findFunction(criteria)
    if math.type(criteria) ~= nil then
        for _, fn in ipairs(functions) do
            if fn.id == criteria then return fn end
        end
    elseif type(criteria) == 'table' then
        for _, fn in ipairs(functions) do
            if matchCriteria(fn, criteria) then return fn end
        end
    end
    return nil
end


function findFunctions(criteria)
    local res = {}
    if type(criteria) == 'table' then
        for _, fn in ipairs(functions) do
            if matchCriteria(fn, criteria) then table.insert(res, fn) end
        end
    end
    return res
end

local topicRepetitions = {}
local topicFunction = {}


--
-- This function is called on message on every monitored topic_read
--
function handleTrigger(topic, payload, retained)
	
	local data = json:decode(payload)
	
	if topicRepetitions[topic] == nil then
		topicRepetitions[topic] = 0
	end

	--
	-- Get the thresholds 
	--
	local func = topicFunction[topic]
	payload_data = json:decode(payload)

	if func.meta.max_value then
		max_value = tonumber(func.meta.max_value)

		if payload_data.value > max_value then
			topicRepetitions[topic] = topicRepetitions[topic] + 1
			sendNotification(topic, payload_data, "over")
			return
		end
	end

	if func.meta.min_value then
		min_value = tonumber(func.meta.min_value)

		if payload_data.value < min_value then
			topicRepetitions[topic] = topicRepetitions[topic] + 1
			sendNotification(topic, payload_data, "under")
			return
		end
	end

	--
	-- If there have been repetitions_limit or more messages before this 
	-- this means that this is the first value that are ok after a period 
	-- outsid the limits. Send recovery.
	--
	local repetitions_limit = 0
	if func.meta.repetitions then
		repetitions_limit = tonumber(func.meta.repetitions)
	end

	if topicRepetitions[topic] >= repetitions_limit then
		sendNotification(topic, payload_data, "recovery")
		topicRepetitions[topic] = 0
	end
end

function createStatusFunction()
	if not cfg.status_function then return end
	
	if cfg.status_function ~= "Ja" then return end

	print("Will create status function")

        local func = findFunction({
                topic_read = statusTopic
        })

	print(json:encode(func))
        
	if func == nil then
                fn = {
                        type = "appstatus",
                        installation_id = app.installation_id,
                        meta = {
                                name = app.name .. " - app status",
                                topic_read = statusTopic
			}
		}

		fn["meta"]["metric_monitor.max_silent_time"] = tostring(statusInterval + 30) .. "s"

		print("Creating" .. json:encode(fn))
                lynx.createFunction(fn)
	end
end

function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end


function reportStatus(status) 
	if not cfg.status_function then return end
	if cfg.status_function ~= "Ja" then return end

	count = tablelength(topicFunction)
	
	local msg = {
		status = status
	}

	local payloadData = {
		value = count,
		timestamp = edge:time(),
		msg = json:encode(msg)
	}

	mq:pub(statusTopic, json:encode(payloadData))
end

function onFunctionsUpdated()
	print("Functions updated")
	
	for topic, _ in pairs(topicFunction) do
		print("Unbind " .. topic)
		mq:unbind(topic, handleTrigger)
	end

	topicFunction = {}

	for _, triggerFunction in pairs(findFunctions(criteria)) do
		local triggerTopic = triggerFunction.meta.topic_read

		print("Adding " .. triggerTopic)

		-- Keep mapping between topic and function. In the case
		-- of two functions having the same topic the last one
		-- in this loop will be used.
		topicFunction[triggerTopic] = triggerFunction

		mq:bind(triggerTopic, handleTrigger)
	end
	reportStatus("updated functions to monitor")
end

function onCreate()
	print("On create running")
	createStatusFunction()
	reportStatus("created")
end

function onDestroy()
	print("On destroy running")
        local func = findFunction({
                topic_read = statusTopic
        })

	if func ~= nil then
        	lynx.deleteFunction(func.id)
	end
end


function reportRunning()
	reportStatus("running")
end

function onStart()
	reportStatus("starting")
	local t = timer:interval(statusInterval, reportRunning)

	criteria = { max_value = '.*' }

	for _, triggerFunction in ipairs(findFunctions(criteria)) do
		local triggerTopic = triggerFunction.meta.topic_read


		print("Adding " .. triggerTopic)

		-- Keep mapping between topic and function. In the case
		-- of two functions having the same topic the last one
		-- in this loop will be used.
		topicFunction[triggerTopic] = triggerFunction

		mq:sub(triggerTopic, 1)
		mq:bind(triggerTopic, handleTrigger)
	end
end

function sendNotification(topic, payload, notificationType)

	if cfg.notification_output == nil then return end

	local func = topicFunction[topic]
	local dev = findDevice(tonumber(func.meta.device_id))

	local repetitions_limit = 0
	
	if func.meta.repetitions then
		repetitions_limit = tonumber(func.meta.repetitions)
	end

	repetitions = topicRepetitions[topic]

	if repetitions == repetitions_limit or notificationType == "recovery" then
	    if notificationType == "recovery" then 
		subject = "Återställning: " .. dev.meta.name
	    	reportStatus("sending recovery for " .. dev.meta.name)
	    end
	    if notificationType == "over" then 
		subject = "Medicinskåp: " .. dev.meta.name .. " är över rekomenderad temperatur"
	    	reportStatus("sending over temp alarm for " .. dev.meta.name)
	    end
	    if notificationType == "under" then 
		subject = "Medicinskåp: " .. dev.meta.name .. " är under rekomenderad temperatur"
	    	reportStatus("sending under temp alarm for " .. dev.meta.name)
	    end


	    if not payload.timestamp then
		    payload.timestamp = edge:time()
	    end

	    print("Sending Notification")
	    local payloadData = {
		value = payload.value,
		timestamp = math.floor(payload.timestamp),
		func = func,
		dev = dev,
		subject = subject,
		notificationType = notificationType
	    }

	    print(json:encode(payloadData))
            for _, n in ipairs(cfg.notification_output) do
	        lynx.notify(n, payloadData)
	    end
	end
end
