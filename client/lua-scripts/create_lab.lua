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
-- create_lab: script to create a NTNU lab.
--
parent=readstr("What is the parent ID of the lab?\n");
name=readstr("What is the lab name?\n");
print ("Parent of lab: " .. parent .. "\n");
print ("Lab name: " .. name .. "\n");
ok = readstr("Do you want to create lab? [Y/N]\n","Y");
if (string.upper(ok) == "Y") then
   print ("Creating lab " .. name .. " group\n");
   params={};
   params.parent=parent;
   params.name=name;
   lresult=aurora("createGroup",params);
   if (lresult.err == 0) then
      -- create roles group under the lab      
      print ("   Successfully created lab " .. name .."\n");
      print ("Creating roles group on lab...\n");
      labid = lresult.id;
      rparams={};
      rparams.parent=labid;
      rparams.name="roles";
      rresult=aurora("createGroup",rparams);
      if (rresult.err == 0) then
         -- create user roles group
         print ("   Successfully created roles group under lab" .. "\n");
         print ("Creating user group under roles...\n");
         urparams={};
         urparams.parent=rresult.id;
         urparams.name=name .. "_user";
         urres=aurora("createGroup",urparams);
         if (urres.err == 0) then
            -- create admin roles group
            print ("   Successfully created user roles group " .. urparams.name .. " for lab " .. name .. "\n");
            print ("Creating admin group under roles...\n");
            arparams={};
            arparams.parent=rresult.id;
            arparams.name=name .. "_admin";
            arres=aurora("createGroup",arparams);
            if (arres.err == 0) then
               -- set perms
               print ("   Successfully created admin roles group " .. arparams.name .. " for lab " .. name .. "\n");
               -- set perms for users on lab
               print ("Setting permissions for users on lab...\n");
               uperms={};
               uperms.user=urres.id;
               uperms.id=labid;
               uperms.grant={"COMPUTER_READ"};
               pures=aurora("setGroupPerm",uperms);
               -- set perms for admins on lab
               print ("Setting permissions for admins on lab...\n");
               aperms={};
               aperms.user=arres.id;
               aperms.id=labid;
               aperms.grant={"COMPUTER_CREATE","COMPUTER_CHANGE","COMPUTER_MOVE","COMPUTER_READ"};
               pares=aurora("setGroupPerm",aperms);
               -- set perms for admins on roles group
               print ("Setting permissions for admins on roles group...\n");
               rperms={};
               rperms.user=arres.id;
               rperms.id=rresult.id;
               rperms.grant={"GROUP_MEMBER_ADD"};
               rperms.deny={"COMPUTER_CREATE"};
               prres=aurora("setGroupPerm",rperms);
               if ((pures.err == 0) and (pares.err == 0) and (prres.err == 0)) then
                  print ("   Successfully set all permissions for lab...\n");
                  print ("   Successfully completed creating lab " .. name .."\n");
               end
            end
         end
      end
   end
end
