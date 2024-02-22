// Copyright (C) 2021-2024 Jan Frode Jæger (jan.frode.jaeger@ntnu.no), NTNU, Trondheim, Norway
//
// This file is part of AURORA, a system to store and manage science data.
//
// AURORA is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// AURORA is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// AURORA. If not, see <https://www.gnu.org/licenses/>.
//
// Description: Class to cache entity tree in memory and read from AURORA REST-server when needed
//
import { AuroraDataLoader } from "./_auroradataloader";

export class AuroraTreeCache {
    // define class constructor
    // count - number of branches that are cached maximum
    // depth - intial depth at which cache is kept for a branch
    constructor (count,timeout,exclude,params) {
        // group tree
        this.groups={};
        this.groups.items={};
        this.groups.fetched=0;
        // hash of tree branches
        this.branches={};
        this.branches.fetched=0;
        this.branches.items={};
        // define root-branch, which is limited in depth
        // and exclude no types
        this.branches.items[1]={};
        this.branches.items[1].fetched=0;
        this.branches.items[1].depth=1;
        this.branches.items[1].exclude=[];
        this.branches.items[1].branch={};
        // the composite tree itself        
        this.treeval={};
        // number of branches allowed in the branches hash
        this.countval=(/^\d+$/.test(count) ? count : 3);
        if (this.countval < 1) { this.countval = 1; }
        // timeout before cache is reloaded, default is 1 hour
        this.timeoutval=(/^\d+$/.test(timeout) ? timeout : 3600)        
        // make a dataloader object
        this.dataloader=new AuroraDataLoader("getTree");
        // add branch includes. It must be an array of strings
        if (Array.isArray(exclude)) { 
            // ensure that exclude does not *include* GROUP.
            let list=[];
            exclude.forEach((item) => {
                if (String(item).toUpperCase !== "GROUP") { list.push(item); }
            });
            // add cleaned list to variable
            this.excludeval=list;
        
        }
        else if (exclude === undefined) { this.excludeval=["USER","DATASET"]; }
        // setup params values
        this.paramsval={};
        if ((params !== undefined) && (typeof params == "object")) { this.params(params); }        
    } 

    // get group tree
    async getGroups() {
        let params={};
        // get root and all group children
        // but only GROUP-type
        params.id=1;
        params.include=["GROUP"];
        // add any extra params
        for (let pkey in this.paramsval) {
            params[pkey]=this.paramsval[pkey];
        }        
        
        // load groups data
        let grps = await this.dataloader.load(params);
        
        // return groups data
        return grps;        
    }

    // get a branch 
    async getBranch(parent) {
        // reread branch
        let params={};
        params.id = parent;
        // some types may be excluded, either through local setting 
        // or global
        params.exclude = (this.branches.items[parent] !== undefined && 
                          this.branches.items[parent].exclude !== undefined ? this.branches.items[parent].exclude : this.exclude());
        // some nodes may have depth restrictions
        // typically only root (=1)
        if ((this.branches.items[parent] !== undefined) &&
            (this.branches.items[parent].depth !== undefined)) {
            params.depth=this.branches.items[parent].depth;
        }
        // add any extra params
        for (let pkey in this.paramsval) {           
            params[pkey]=this.paramsval[pkey];
        }    
        // load branch data
        let br = await this.dataloader.load(params);
        // return branch data
        return br;        
    };

    // method to get the whole tree
    async get() {
        // check if we need to get groups or if we have a cache
        const now = Math.floor(new Date().getTime() / 1000);
        if ((Object.keys(this.groups.items).length == 0) || (this.groups.fetched == undefined) ||
            ((this.groups.fetched + this.timeout()) < now)) {
            // we need to reread cache
            let grp=await this.getGroups();

            await grp;

            if (grp.err === 0) {
                // fetched data sucessfully
                this.groups.fetched = now;
                this.groups.items = grp.tree;                
            }
        }

        // check if we need to update any of the branches
        if ((Object.keys(this.branches.items).length == 1) || (this.branches.fetched == undefined) ||
            ((this.branches.fetched + this.timeout()) < now)) {
            // we need to reread one or more branches
            for (let key in this.branches.items) {
                if ((/^\d+$/.test(key)) &&
                    ((this.branches.items[key].fetched + this.timeout()) < now)) {                    
                    // it has expired - reread branch
                    let branch=await this.getBranch(key);

                    await branch;

                    if (branch.err === 0) {
                        // overwrite old branch info
                        this.branches.items[key].branch = branch.tree;
                        // set new fetched time
                        this.branches.fetched=now;
                        this.branches.items[key].fetched=now;
                    }    
                }
            }
        }
        // we are ready to merge groups and branches into a tree
        // first we need to traverse the new group-data and compare with existing tree
        // copy state info from existing tree into new group-tree, if any
        let ntree={};
        for (let key in this.groups.items) {                
            // check if we have any leaf data, we only check the top tree node
            if (this.branches.items[key] != undefined) {
                // this is the top part of the branch - replace with what we get from leaf                
                for (let bkey in this.branches.items[key].branch) {
                    // add all branch key to new tree
                    // but ony if not added already
                    if (ntree[bkey] == undefined) {
                        ntree[bkey] = this.branches.items[key].branch[bkey];                    
                    } else {
                        // key exists already - just add children
                        // adding is accumulative, but not repeated
                        this.branches.items[key].branch[bkey].children.forEach((child) => {
                            if (!ntree[bkey].children.includes(child)) {
                                // child does not exist already - add it
                                ntree[bkey].children.push(child);
                            }
                        });  
                        // also add group ones
                        this.groups.items[bkey].children.forEach((child) => {
                            if (!ntree[bkey].children.includes(child)) {
                                // child does not exist already - add it
                                ntree[bkey].children.push(child);
                            }
                        });           
                    }
                }
            } else {
                // we dont have this branch in the leaf data - use the group one
                // add group to new tree if it doesnt exist already
                if (ntree[key] == undefined) { ntree[key]=this.groups.items[key]; }
            }

            // check if we have old state data from old tree
            if (this.treeval[key] != undefined) {
                if (this.treeval[key].expanded != undefined) { ntree[key].expanded = this.treeval[key].expanded }
            }
            // check if we have expanded state or not now, if not assume is is collapsed
            if ((ntree[key] != undefined) && (ntree[key].expanded == undefined)) { ntree[key].expanded = false; }            
        }

        // set instance tree to new tree
        this.treeval = ntree;

        // we now have a fully composited tree that we can return
        return ntree;
    }

    // expand a branch
    // expanding a top branch will 
    // shift out the oldest used branch
    async expand(id) {
        // first check if ID to expand is in branches
        if (this.branches.items[id] !== undefined) {            
            // this id exists in branches - toggle it
            this.treeval[id].expanded = true;
            // do we have any timeouts that require reread?
            if (this.isTimeout()) {
                await this.get();
            }
        } else {
            // check if we are expanding a new top branch, root excluded
            if ((id !== 1) && (this.treeval[id].parent === 1)) {
                // this is a top branch - shuffle it in place instead of another 
                // in branches if branches has reached its intended size
                if (Object.keys(this.branches.items).length >= (this.count() + 1)) {
                    // remove oldest branch from sync by setting its fetched timestamp to infinity
                    // let oldest={ time: 2**64-1, key: "" };
                    let oldest={ time: 0, key: "" };
                    for (let key in this.branches.items) {
                        // root-node (=1) can never be removed from update
                        if ((key !== 1) && (oldest.time < this.branches.items[key].fetched)) {
                            oldest.time=this.branches.items[key].fetched;
                            oldest.key=key;
                        }
                    }
                    // set the oldest branch to infinity to stop it from being updated 
                    // through REST-server calls
                    this.branches.items[oldest.key].fetched=2**64-1;
                }
                // add top branch to branches - force a read
                this.branches.items[id]={};
                this.branches.items[id].fetched=0;
                this.branches.items[id].branch={};
                this.branches.fetched=0;
                // expand the new branch            
                this.treeval[id].expanded = true;
                // go get the data
                await this.get();                               
            } else {
                // not a top branch - just toggle
                this.treeval[id].expanded = true;   
                // do we have any timeouts that require reread?
                if (this.isTimeout()) {
                    await this.get();
                }
            }
        }
        return this.treeval;
    }

    // collapse a branch
    async collapse(id) {
        // upon collapse, we should close the node
        if (this.treeval[id] !== undefined) { this.treeval[id].expanded = false; }
        return this.treeval;
    }

    // toggle a branch for being updated
    // oldest branch is removed from update if count has been reached
    async update(id) {
        if (/^\d+$/.test(id)) {
            if (this.branches.items[id] !== undefined) {
                // branch exists in cache - toggle it for updating by            
                // check if we have other branches that needs to go out
                if (Object.keys(this.branches.items).length >= (this.count() + 1)) {
                    // remove oldest branch from sync by setting its fetched timestamp to infinity
                    let oldest={ time: 2**64-1, key: "" };
                    for (let key in this.branches.items) {
                        // root-node (=1) can never be removed from being updated
                        if ((key !== 1) && (oldest.time > this.branches.items[key].fetched)) {
                            oldest.time=this.branches.items[key].fetched;
                            oldest.key=key;
                        }
                    }
                    // set the oldest branch to infinity to stop it from being updated 
                    // through REST-server calls
                    this.branches.items[oldest.key]=2**64-1;                    
                }
                // setting fetched time to 0 to force re-read
                this.branches.items[id].fetched=0;
                this.branches.fetched=0;
                // do a reread
                let wait=await this.get();
                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }

    // refresh all of active cache
    // but with a possibility of a smart cache refresh
    // where a list of entity IDs are specified and only branches containing
    // those are refreshed
    async refresh(ids) {
        // update fetched time on groups
        this.groups.fetched=0;
        // update fetched time on top of branches
        this.branches.fetched=0;
        // variable to signal if ids was found or not
        let idsfound=false;        
        if ((ids != undefined) && (Array.isArray(ids))) {
            // we have ids that we can use to only refresh the affected
            // branches
            let found=0;
            for (let i=0; i < ids.length; i++) {
                let id=ids[i];
                let idfound=false;
                // go through each branch and see if it is present there (or not)
                for (let key in this.branches.items) {
                    // check if the given id exists in this branch or not?
                    if (this.branches.items[key].branch[id] != undefined) {
                        // it exists in this branch - refresh it
                        this.branches.items[key].fetched=0;                        
                        idfound=true;
                    }
                }
                // update found only once for each id found.
                if (idfound) { found++; }
            }
            // check if found matches the length of ids
            if (found == ids.length) {
                // the number of ids found matches the size of the ids array
                // all ids have been located
                idsfound=true;
            }
        }
        // check if we have found all ids or not?    
        if (!idsfound) {
            // we do not have any ids to smart refresh from or they were not found, so
            // update fetched time on all active branches
            for (let key in this.branches.items) {
                // only set branches for refresh that are active
                if (this.branches.items[key].fetched < (2**64-1)) {
                    // this branch is active and is being cached
                    // mark it for refresh
                    this.branches.items[key].fetched=0;
                }
            }
        }
        // we are ready to ask for a refresh
        let ntree = await this.get();
        // return the result
        // of the refresh
        return ntree;
    }

    // check if any of the cache has timed out
    isTimeout() {
        const now = Math.floor(new Date().getTime() / 1000);
        if (((this.groups.fetched + this.timeout()) < now) ||
            ((this.branches.fetched + this.timeout()) < now)) {
            // something has timed out
            return true;
        } else {
            // nothing has timed out
            return false;
        }
    }

    // return the tree object instancestance    
    tree() {
        return this.treeval;
    }

    // set or get the number of allowed branches that are 
    // actively being updated
    count(no) {
        if (no !== undefined) {
            // this is a set
            let old = this.countval;
            this.countval = (/^\d+$/.test(no) ? no : this.countval);
            if (old > this.countval) {
                // count was decreased - we have to remove branches
                let diff = Math.floor(old - this.countval);
                for (let i=1; i <= diff; i++) {
                    // remove the oldest branches from being actively updated
                    let oldest={ time: 2**64-1, key: "" };
                    for (let key in this.branches.items) {
                        // root-node (=1) can never be removed from being updated
                        if ((key !== 1) && (oldest.time > this.branches.items[key].fetched)) {
                            oldest.time=this.branches.items[key].fetched;
                            oldest.key=key;
                        }
                    }
                    // set the oldest branch to infinity to stop it from being updated 
                    // through REST-server calls
                    this.branches.items[oldest.key] = 2**64-1;         
                }
            }
        } else {
            // this is a get
            return this.countval;
        }
    }

    // set or get exclude value
    exclude(value) {
        if ((value !== undefined) && (Array.isArray(value))) {
            // this is a set
            let list=[];
            value.forEach((item) => {
                let name=String(item).toUpperCase();
                if (name !== "GROUP") { list.push(item); }
            });
            // add cleaned list to variable
            this.excludeval=list;
            // update fetched-timestamps to force reload of branches
            this.branches.fetched=0;
            // go through each branch and update fetched timestamp
            let now = Math.floor(new Date().getTime() / 1000);
            for (let key in this.branches.items) {
                // only update branches that are not in the future (non-update branches)
                if (this.branches.items[key].fetched <= now) {
                    // force an update of this branch
                    this.branches.items[key].fetched = 0;
                }
            }
        }
        // both set and get returns
        // value of exclude
        return this.excludeval;
    }

    // set or get timeout value
    timeout(val) {
        if (val !== undefined) {
            // set a new timeout value
            this.timeoutval=(/^\d+$/.test(val) ? val : this.timeoutval);
            return this.timeoutval;
        } else {
            // this is a get
            return this.timeoutval;
        }
    }

    // set or get params values
    params(val) {
        if (val !== undefined) {
            // set a new params value
            if (typeof val == "object") {
                // go through each key in object and add if correct type
                // we accept: string, number, boolean and bigint.
                let nval = {};
                for (let pkey in val) {
                    if ((typeof val[pkey] == "string") ||
                        (typeof val[pkey] == "number") ||
                        (typeof val[pkey] == "boolean") ||
                        (typeof val[pkey] == "bigint")) {
                        nval[pkey] = val[pkey];
                    }
                }
                // overwrite internal value for params if
                // we have one or more values in the new object (nval)
                if (Object.keys(nval).length > 0) {
                    this.paramsval = nval;                
                    // update fetched-timestamps to force reload of branches
                    this.branches.fetched=0;
                    // go through each branch and update fetched timestamp
                    let now = Math.floor(new Date().getTime() / 1000);
                    for (let key in this.branches.items) {
                        // only update branches that are not in the future (non-update branches)
                        if (this.branches.items[key].fetched <= now) {
                            // force an update of this branch
                            this.branches.items[key].fetched = 0;
                        }
                    }
                }    
            }    
        } 
        // both get and set return current value
        return this.paramsval;
    }
}
