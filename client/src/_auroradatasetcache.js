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
// Description: Class to cache dataset entries in memory and read from AURORA REST-server when needed this gives results as if it was the REST-server (same return structure)
//
import { AuroraDataLoader } from "./_auroradataloader";

export class AuroraDatasetCache {
    // define class constructor
    constructor (size,order="DESC",sortby="system.dataset.time.expire",sorttype=0) {
        if ((size === undefined) || (!/^\d+$/.test(size))) {
            // cache size is invalid or not defined - set default
            this.size = 11000;
        } else { 
            // set cache size to specified size
            this.size = size;
        }
        // set data to empty object
        this.data = {};
        // has data been loaded or not?
        this.loaded = false;
        // what is the page no and the number of entries on the page
        // and what are the total number of hits
        this.offset = 1;
        this.count = 0;
        this.total = 0;
        this.orderval = order;
        this.sortbyval = sortby;
        this.sorttypeval = sorttype;
        // set searchstruct
        this.searchstruct={};
    }

    // attempt to get a certain page of cache of
    // given length
    async page (offset,count) {
        // some default values
        if (offset < 1) { offset = 1; } 
        if (count < 1) { count = 10; }
        if (count > this.size) { count = size; } // we do not allow asking for more than cache-size at a time
        // check if we have fetched data already?        
        if ((!this.loaded) ||
            (offset < this.offset) ||
            ((offset > (this.offset+this.count)) && ((this.offset+this.count) < this.total)) ||
            (((offset + count) > (this.offset + this.count)) && ((this.offset + this.count) < this.total))) {
            // we do not have it in cache - it needs to be loaded
            let loader = new AuroraDataLoader("getDatasets");
            let params={};
            // do some heuristics on the offset, to ensure the caching is in effect as much as possible
            let coffset = offset; // cache offset
            if (offset < this.offset) {
                // we want to avoid as many reloading / REST-server operations as possible
                // we assume people most of the time flip between pages
                if ((offset > this.size / 2)) { coffset = Math.round(offset - (this.size / 2)); } // put the cache as much on both sides of offset                           
                else { coffset = 1; } // cache from the beginning
            } else if (offset === 1) {
                coffset = 1;
            } else {    
                coffset = Math.round(offset - (this.size / 2)); // put cache as much on both sides of offset
            }
            params.offset = coffset;
            // we are going to load more than what was asked for, so that we fill the cache
            params.count = this.size;
            // set sort order
            params.sort = this.orderval;
            // set what to sort by
            params.sortby = this.sortbyval;
            // set how to sort, alphanumerical vs numerical etc.
            params.sorttype = this.sorttypeval;
            // add the search structure
            params.metadata = this.searchstruct;
            // load more data
            let result = await loader.load(params);

            await result;

            // update what we have loaded
            this.offset=coffset;
            this.count=result.returned;
            this.total=result.total;
            this.data=result;

            // update the loaded flag
            if (result.err === 0) { this.loaded = true; } else { this.loaded = false; }            
        }
        // check if things are now loaded, if so get the data
        if (this.loaded) {
            // we have the required result in our cache already
            let result={};
            result.datasets={};
            let basecount=0;
            for (let i=offset; i < (offset+count); i++) {                
                if (i > ((this.offset + this.count)-1)) { break; } // no more results to be had
                basecount++;
                result.datasets[basecount] = this.data.datasets[(i - this.offset)+1];
            }
            // update returned
            result.returned = basecount;
            result.total = this.total;
            result.err = this.data.err;
            result.errstr = this.data.errstr;
            result.received = this.data.received;           
            result.delivered = this.data.delivered;
            // return the page data asked for
            return result;            
        } else {
            // some kind of error
            let result={};
            result.err=this.data.err;
            result.errstr=this.data.errstr;
            return result;
        }
    }

    // set/get sort direction of columns
    order(dir) {
        if (dir !== undefined) {
            // set direction
            dir = String(dir).toUpperCase();
            if (dir == 'ASC') {
                this.orderval = 'ASC';                
            } else {
                this.orderval = 'DESC';
            }
            // change of order means loaded is false
            this.loaded = false;
        } else {
            // get direction
            return this.orderval;
        }   
    }

    // set/get what to sort by
    sortby(sb) {
        if (sb !== undefined) {            
            this.sortbyval = sb;            
            // change of sortby means loaded is false
            this.loaded = false;
        } else {
            // get direction
            return this.sortbyval;
        }   
    }

     // set/get how the sort is performed
     sorttype(st) {
        if (st !== undefined) {            
            this.sorttypeval = st;
            // change of sorttype means loaded is false
            this.loaded = false;
        } else {
            // get direction
            return this.sorttypeval;
        }   
    }

    // set or get searchstruct/SQLStruct hash
    searchStruct(struct) {
        if ((struct == undefined) || (typeof struct !== 'object')) {
            // return current searchstruct;
            return this.searchstruct;
        } else {
            // set new searchstruct
            this.searchstruct = struct;
            // because we have a new searchstruct, cache needs to be loaded again
            this.loaded = false;
        }
    }

    // get/set cache size
    size(sz) {        
        if (sz !== undefined) {
            // set size
            // default value
            if (!/^\d+$/.test(sz)) {                
                this.size = 11000;
            } else {
                this.size = sz;
            }
            // all size change requires reload of cache
            this.loaded = false;
        } else {
            // get size
            return this.size;
        }
    }
}
