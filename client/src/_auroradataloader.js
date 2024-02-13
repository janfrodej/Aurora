// Copyright (C) 2021-2024 Jan Frode Jæger (jan.frode.jaeger@ntnu.no), NTNU, Trondheim, Norway
//
// This file is part of AURORA, a system to store and manage science data.

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
// _auroradataloader.js - class to load data through a method from an AURORA REST-server
import { call_aurora } from "./_aurora.js";   

export class AuroraDataLoader {
    constructor(method) {
        this.method = method;
        this.result = undefined;
    }

    // run REST-call and attempt to laod data
    async load (params) {
        // call the AURORA REST-server with the relevant method
        this.result = await call_aurora(this.method,params);

        // wait for result
        await this.result;

        // return result of operation        
        return this.result;        
    }

    // return the data, if any
    data() {
        return this.result;
    }
}

