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
-- script to create research group
--
parent=readstr("Research Group's parent ID:\n");
name=readstr("Research Group name:\n");
print ("Parent: " .. parent .. "\n");
print ("Research Group Name: " .. name .. "\n");
ok=readstr("Do you want to create Research Group? [Y/N]\n","Y");
if (string.upper(ok) == "Y") then
   -- we are creating the group
   rgpar={};
   rgpar.parent=parent;
   rgpar.name=name;
   print ("Creating research group \"" .. name .. "\"...\n");
   rgres=aurora("createGroup",rgpar);
   if (rgres.err == 0) then
      print ("   Research group created successfully...\n");
      -- rg group created - create rest of structure
      rolpar={};
      rolpar.parent=rgres.id;
      rolpar.name="roles";
      print ("Creating roles group...\n");
      rolres=aurora("createGroup",rolpar);
      if (rolres.err == 0) then
         print ("   Roles group created successfully...\n");
         -- create roles group's groups
         -- first create roles guest group
         guestpar={};
         guestpar.parent=rolres.id;
         guestpar.name=name .. "_guest";
         print ("Creating roles guest group...\n");
         guestres=aurora("createGroup",guestpar);
         -- create roles user group
         userpar={};
         userpar.parent=rolres.id;
         userpar.name=name .. "_user";
         print ("Creating roles user group...\n");
         userres=aurora("createGroup",userpar);
         -- create roles admin group
         adminpar={};
         adminpar.parent=rolres.id;
         adminpar.name=name .. "_admin";
         print ("Creating roles admin group...\n");
         adminres=aurora("createGroup",adminpar);
         if ((guestres.err == 0) and (userres.err == 0) and (adminres.err == 0)) then
            print ("   guest-, user-, and admin roles groups created successfully...\n");
            -- all roles group created successfully - set perms
            -- set perms for guests
            perms={};
            perms.id=rgres.id;
            perms.user=guestres.id;
            perms.grant={"DATASET_CREATE"};
            print ("Setting guest perms on research group...\n");
            gpres=aurora("setGroupPerm",perms);
            -- set perms for users
            perms.id=rgres.id;
            perms.user=userres.id;
            perms.grant={"DATASET_LIST",
                         "DATASET_LOG_READ",
                         "DATASET_METADATA_READ",
                         "DATASET_READ",
                         "DATASET_CREATE",
                         "DATASET_CLOSE"};
            print ("Setting user perms on research group...\n");
            upres=aurora("setGroupPerm",perms);
            -- set perms for admins
            perms.id=rgres.id;
            perms.user=adminres.id;         
            perms.grant={"DATASET_CHANGE",
                         "DATASET_CREATE",
                         "DATASET_CLOSE",
                         "DATASET_DELETE",
                         "DATASET_LIST",
                         "DATASET_LOG_READ",
                         "DATASET_METADATA_READ",
                         "DATASET_MOVE",
                         "DATASET_PERM_SET",
                         "DATASET_PUBLISH",
                         "DATASET_READ",
                         "DATASET_RERUN"};
            print ("Setting admin perms on research group...\n");
            apres=aurora("setGroupPerm",perms);
            -- set roles permissions
            perms.id=rolres.id;
            perms.user=1;
            perms.deny={"DATASET_CREATE"};
            print ("Setting root permissions on roles...\n");
            denyres=aurora("setGroupPerm",perms);
            perms.id=rolres.id;
            perms.user=adminres.id;
            perms.grant={"GROUP_MEMBER_ADD",
                         "GROUP_CREATE",
                         "GROUP_DELETE",
                         "GROUP_MOVE",
                         "GROUP_PERM_SET"};
            print ("Setting admin permissions on roles...\n");
            arres=aurora("setGroupPerm",perms);
            -- check all results
            if ((gpres.err == 0) and (upres.err == 0) and
                (apres.err == 0) and (denyres.err == 0) and
                (arres.err == 0)) then
               -- all successful
               print ("\nResearch group and all its groups and permissions successfully created and set...\n");
            end
         end
      end
   end
end
