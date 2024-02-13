--
-- Copyright(C) 2019-2024 Jan Frode Jæger, NTNU, Trondheim, Norway
--
-- This file is part of AURORA, a system to store and manage science data.
--
-- AURORA is free software: you can redistribute it and/or modify it under 
-- the terms of the GNU General Public License as published by the Free 
-- Software Foundation, either version 3 of the License, or (at your option) 
-- any later version.
--
-- AURORA is distributed in the hope that it will be useful, but WITHOUT ANY 
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
-- FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with 
-- AURORA. If not, see <https://www.gnu.org/licenses/>. 
--
-- script to create a computer
labid = readstr ("What is the parent entity ID of the lab?: \n");
print ("Lab ID: " .. labid .. "\n");

-- get computer template so we know which metadata to ask for
print ("Retrieving template for the lab in question. Please wait...\n");
params={}
params.id=labid;
params.type="COMPUTER";
tmpl = aurora("getAggregatedTemplate",params);

-- go through template and ask for input
cparams={};
cparams.parent=labid;
cparams.metadata={};
for k,v in pairs(tmpl.template) do
   -- we will handle knownhosts separately
   if (k ~= ".system.task.param.knownhosts") and (k ~= ".computer.bookitlab.assets") then
      cparams.metadata[k]=readstr("Please fill in: " .. k .."\n",v.default);
   end
end

-- print (dumper(tmpl));

assets = readstr ("Computer BookitLab asset tags (comma separated): \n");
assetarr = split(assets,",");
if (#assetarr > 0) then
   cparams.metadata[".computer.booktitlab.assets"]=assetarr;
end

-- get host public keys
print ("Retrieving public ssh keys for host " .. cparams.metadata[".system.task.param.host"] .. ". Please wait...\n");
params={};
params.host=cparams.metadata[".system.task.param.host"];
pubkeys = aurora("getHostSSHKeys",params);

if (pubkeys.err == 0) then
   print ("Available SSH keys to include in knownhosts:\n\n");
   for k,v in pairs(pubkeys.sshkeys) do
      print ("   " .. k .. "\n");
   end
   keychoice = readstr("Please select one of the SSH keys below by writing the type name: \n","ssh-rsa");
   if (pubkeys.sshkeys[keychoice] ~= nil) then
      -- set correct value in metadata
      cparams.metadata[".system.task.param.knownhosts"] = cparams.metadata[".system.task.param.host"] .. " " .. keychoice .. " " .. pubkeys.sshkeys[keychoice];      
   end
end

-- print (dumper(pubkeys));

print ("The following data is available to create a computer:\n");

print (dumper(cparams));

ok = readstr("Do you want to proceed with create computer? [Y/N]: \n","Y");
if (string.upper(ok) == "Y") then
   result = aurora ("createComputer",cparams);

   if (result.err == 0) then
      print ("Success creating computer...\n");
   end
end 
