--            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
--                    Version 2, December 2004
--
-- Copyright (C) 2011-2012 tin@sluc.org.ar and dererk@madap.com.ar
--
-- Everyone is permitted to copy and distribute verbatim or modified
-- copies of this license document, and changing it is allowed as long
-- as the name is changed.

--            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
--   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
--
--  0. You just DO WHAT THE FUCK YOU WANT TO.
----------------------------------------------------------------------
--
-- TODO Remember registrations pending to admins

local datamanager = require "util.datamanager";
local st = require "util.stanza";
local host = module:get_host();
local nodeprep = require "util.encodings".stringprep.nodeprep;
local adhoc_new = module:require "adhoc".new;
local dataforms_new = require "util.dataforms".new;
local jid_split = require "util.jid".split;

module:hook("user-registered", function(event)
	local username = event.username;
        local new_user_jid = username ..'@'.. host;

        module:log("info", "New account username " .. new_user_jid);
	local pendings = datamanager.load(nil, host, "pending");
	if pendings == nil then
		pendings = {};
	end
	pendings[username] = true;
	datamanager.store(nil, host, "pending", pendings);

end);

function get_pending_jids()
	local pendings = datamanager.load(nil, host, "pending") or {};
	local jids = {};
	for aJID, _ in pairs(pendings) do
		if _ == true then
			jids[#jids+1] = aJID;
		end
	end
	return jids;
end

function delete_pending(jids)
	local pendings = datamanager.load(nil, host, "pending") or {};
	for idx, jid in ipairs(jids or {}) do
		pendings[jid] = nil;
		module:log("info", "Deleted " .. jid .. "@" .. host .." from pending");
	end
	datamanager.store(nil, host, "pending", pendings);
end 

function rejects_registrations(self, data, state)
	local layout = dataforms_new {
		title = "Rejects new account";
		instructions = "Select the jid";

		{ name = "FORM_TYPE", type = "hidden", value = "http://prosody.im/" };
		{ name = "jids_to_rejects", type = "list-multi", required = false, label = "Jabber ids to rejects"};
	};
	if state then
		if data.action == "cancel" then
			return { status = "canceled" };
		end
		local fields = layout:data(data.form);

		for idx, username in ipairs(fields.jids_to_rejects or {}) do
			datamanager.store(username, host, "vcard", nil);
			datamanager.store(username, host, "accounts", nil);
			datamanager.store(username, host, "private", nil);
			datamanager.list_store(username, host, "offline", nil);
			datamanager.store(username, host, "roster", nil);
			datamanager.store(username, host, "privacy", nil);
			module:log("info", "User removed their account: %s@%s", username, host);
			module:fire_event("user-deregistered", { username = username, host = host, source = "mod_moderate_registrations" });
		end
		delete_pending(fields.jids_to_rejects);
		return { status = "completed", info = "Users rejected" };
	else
		return { status = "executing", form = { layout = layout; values = { jids_to_rejects = get_pending_jids() } } }, "executing";
	end
end

function accepts_registrations(self, data, state)
	local layout = dataforms_new {
		title = "Accepts new accounts";
		instructions = "Select the jid";

		{ name = "FORM_TYPE", type = "hidden", value = "http://prosody.im/" };
		{ name = "jids_to_accepts", type = "list-multi", required = false, label = "Jabber ids to accepts"};
	};
	if state then
		if data.action == "cancel" then
			return { status = "canceled" };
		end
		local fields = layout:data(data.form);
		delete_pending(fields.jids_to_accepts);
		return { status = "completed", info = "Users approved" };
	else
		return { status = "executing", form = { layout = layout; values = { jids_to_accepts = get_pending_jids() } } }, "executing";
	end
end

module:hook("authentication-success", function(event)
	local username = event.session.sasl_handler.username;
	local data = datamanager.load(nil, host, "pending") or {};
	if data[username] == true then
		module:log("info", "account username is pending " .. username .. "@" .. host);

		local moderation_stanza =
			st.message({ to = username.."@"..host, from = host })
			:tag("body"):text("Your registration is pending.");
		event.session.send(moderation_stanza);
		event.session:close();
		return true;
	end
end);

local descriptor_accept = adhoc_new("Accepts registrations", "accepts_registrations", accepts_registrations, "admin");
local descriptor_reject = adhoc_new("Rejects registrations", "rejects_registrations", rejects_registrations, "admin");

module:add_item ("adhoc", descriptor_reject);
module:add_item ("adhoc", descriptor_accept);
