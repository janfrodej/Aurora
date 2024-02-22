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
// settings for the AURORA Web-client
//
// Description: Fetches the AURORA configuration file. Used by the whole AURORA application.
//
import YAML from 'yaml';

// read config information from file
export async function getConfig (location=window.location.origin+window.location.pathname+"/settings.yaml") {
    const res=await fetch(location, 
        {
            method: "POST",          /* HTTP method */
            credentials: "omit",     /* do not send cookies */
            mode: "cors",            /* its a cross origin request */
            headers: { 
                       "User-Agent": "SvelteAuroraWebClient/1.0B",
                       "Content-Type": "application/yaml",
                       "Accept": "application/yaml",
                     },
        }
        )
        .then((response) => { return response; }
        ); 

    await res;

    // convert body to text
    let text = await new Response(res.body).text(); 
    // convert YAML to an object instance
    let y = YAML.parse(text);
    // return the object instance
    return y;
}
