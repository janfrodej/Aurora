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
import { VERSION } from "./_version.js";
import { getConfig } from "./_config.js";
import { getCookieValue, setCookieValue } from "./_cookies.js";
import { SYSINFO } from "./_tools.js";

export async function call_aurora (method,params,errormsg=true,redirect=true) {
   // await config if needed
   let CFG = await getConfig();
   // automatically fetch and set the authentication type and pw from sessionStorage
   if (params == undefined) { params={}; }
   if ((params["authtype"] == undefined) && (params["authstr"] == undefined)) {
      // attempt to read auth info from cookie
      let as=getCookieValue(CFG["www.cookiename"],"authstr");
      if (as != "") {
         // fill in auth info from cookie-data
         params["authtype"]="Crumbs";
         params["authstr"]=as; 
      }
   }      
   // add client info in the parameters as well
   params["CLIENT_AGENT"] = "Svelte Aurora Web-Client";
   params["CLIENT_VERSION"] = VERSION;
   if (navigator != undefined) {
      params["CLIENT_USERAGENT"] = navigator.userAgent;   
      params["CLIENT_SYSINFO"] = SYSINFO;
   }   

   const res=await fetch("https://"+CFG["aurora.rest.server"]+"/"+method, 
         {
            method: "POST",          /* HTTP method */
            credentials: "omit",     /* do not send cookies */              
            mode: "cors",            /* its a cross origin request */     
            keepalive: true,         /* keep the connection alive over several calls */   
            headers: { 
                       "User-Agent": "SvelteAuroraWebClient/2.0",
                       "Content-Type": "application/json",
                       "Accept": "application/json",                         
                       "Origin": CFG["www.base"],                        
                     },
            body: JSON.stringify(params), /* convert parameters to JSON */
         }
         )
           .then(response => response.json())
           .then(data => {
              if (data.err > 0) { 
                 if (errormsg) { 
                     // create event object
                     const errorEvent = new Event('statusmessage', {
                        bubbles: true,
                        cancelable: false,
                        composed: true
                     });
                     // add error message to event 
                     errorEvent.message=data.errstr;
                     let elem = document.createElement("div");
                     document.body.appendChild(elem);
                     // dispatch errormessage on a div in document
                     elem.dispatchEvent(errorEvent);
                     // remove element
                     elem.remove();
                 }
                 // check if cookie creds has timed out or some other auth SOURCE failure
                 if (Math.floor((data.err / 1000) % 100) == 10) { // SOURCE = AUTH
                    // this is a failure in auth
                    // check the auth issue TYPE
                    let tt=Math.floor((data.err / 10) % 100);
                    if ((tt == 51) || (tt == 53)) {
                       // this is a client input issue or
                       // client auth issue
                       // reset creds                       
                       setCookieValue(CFG["www.cookiename"],"authstr","",CFG["www.domain"],CFG["www.cookie.timeout"],"/");
                    } 
                    // redirect to login-page if error type is gte 50
                    // that is: it is not a REST-server internal or external error 
                    // but only if redirect is true (default)
                    if ((tt >= 50) && (redirect)) { window.location.href=CFG["www.base"]; window.location.reload(); }                    
                 }
              //} else if ((authtype != "") && (authstr != "")) {
              } else if (params["authuuid"] == 1) {
                 // set cookie value for authstr
                 setCookieValue(CFG["www.cookiename"],"authstr",data.authuuid,CFG["www.domain"],CFG["www.cookie.timeout"],"/","Lax");                 
              }
              // return the result of the operation
              return data;
           }).catch(error => { 
              // critical error - alert then return empty result
              if (errormsg) { 
                  // create event object
                  const errorEvent = new Event('statusmessage', {
                     bubbles: true, // bubbel up through parent elements
                     cancelable: false, // not possible to cancel
                     composed: true 
                  });
                  // add error message to event
                  errorEvent.message=error;
                  let elem = document.createElement("div");
                  document.body.appendChild(elem);
                  // dispatch error message on a div in document
                  elem.dispatchEvent(errorEvent);
                  elem.remove();            
              }              
              let o={}
              o["err"]=1;
              o["errmsg"]=error;
              return o;
           }
         );

   // wait for result
   await res;

   // return the result
   return res;   
}
