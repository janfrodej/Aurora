<!--
    Copyright (C) 2021-2024 Jan Frode Jæger (jan.frode.jaeger@ntnu.no), NTNU, Trondheim, Norway

    This file is part of AURORA, a system to store and manage science data.

    AURORA is free software: you can redistribute it and/or modify it under
    the terms of the GNU General Public License as published by the Free
    Software Foundation, either version 3 of the License, or (at your option)
    any later version.

    AURORA is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with
    AURORA. If not, see <https://www.gnu.org/licenses/>.

    Description: Handle login to the AURORA web-client.
-->
<script>    
   import { getConfig } from "./_config";
   import Privacy from "./Privacy.svelte"; 
   import AuroraHeader from "./AuroraHeader.svelte";    
   import { onMount } from 'svelte';
   import { call_aurora } from "./_aurora.js";    
   import Main from "./Main.svelte";     
   import { route, routeparams } from "./_stores.js";
   import Status from "./Status.svelte";
   import StatusMessage from "./StatusMessage.svelte";   
   import { getCookieValue, setCookieValue } from "./_cookies.js";
   import FloatContent from './FloatContent.svelte';
   import Announcement from "./Announcement.svelte";
   
   let CFG={};
   let disabled=false;
   
   let routestr="";
   let username="";
   let pw="";   
   let logon;     
   let logonstarted=false;   
   let redirecturl="";  
   let mode="";

   route.subscribe(value => { routestr = value; });
  
   // handles first time logon attempt
   onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig();
      // update disabled
      disabled = CFG["www.maintenance"]||false;
      // attempt an authentication automatically, but suppress error-messages and redirects to avoid loop
      // and message when this is an auto-attempt
      // only when not disabled
      if (!disabled) {
         logon=call_aurora("doAuth",undefined,false,false);
         logonstarted=true;
      }   

      // get params to page
      const queryString = window.location.search;
      const params = new URLSearchParams(queryString);
      // update route we want to visit, if any
      // but only if not disabled
      if (!disabled) { route.set(params.get("route")||""); }
      // get parameters for page
      let pars={};
      for (let entry of params.entries()) {
         // add all parameters that are not "route" to the parameter hash. Ensure that any encodings of special characters are decoded
         if ((String(entry[0]).toLowerCase() != "route") && (String(entry[0]).toLowerCase() != "routeparams")) { pars[entry[0]] = decodeURIComponent(entry[1]); }
      }
      // check if we have any route params directly specified
      if (/^.+$/.test(routestr)) {
         // save parameters to page
         routeparams.set(pars);
         // set the parameters in the cookie  
         setCookieValue(CFG["www.cookiename"],"routeparams",JSON.stringify(pars),CFG["www.domain"],CFG["www.cookie.timeout"]);
         setCookieValue(CFG["www.cookiename"],"route",routestr,CFG["www.domain"],CFG["www.cookie.timeout"]);
      } else if (/^.+$/.test(getCookieValue(CFG["www.cookiename"],"route"))) {
         // we have a value for route in the cookie - retrieve it
         route.set(getCookieValue(CFG["www.cookiename"],"route"));      
         const r = getCookieValue(CFG["www.cookiename"],"routeparams");
         // this is a JSON string, so we need to convert it
         let p = JSON.parse(r);
         // see if we have any parameters
         if ((typeof p == "object") && (Object.keys(p).length > 0)) {
            // set pars to the object of parameters
            pars = p;
            // remove parameter route and routeparams if they exists
            if (pars["route"] != undefined) { delete pars["route"]; }
            if (pars["routeparams"] != undefined) { delete pars["routeparams"]; }
            // save parameters to page
            routeparams.set(pars);
         }   
      }
      // remove parameters from address bar
      window.history.replaceState({}, document.title,CFG["www.base"]);
	});

   // perform the AuroraID login attempt and set session info on username and pw
   const handleAuroraIdLogin = (e) => {      
      // check for enter or no key-event at all
      if ((e == undefined) || (e.keyCode == 13)) {
         logonstarted=true;      

         // reset authstr-value
         setCookieValue(CFG["www.cookiename"],"authstr","",CFG["www.domain"],CFG["www.cookie.timeout"]);

         // set auth params for REST-call
         let params={};
         params["authtype"]="AuroraID";
         params["authstr"]=username+","+pw;
         params["authuuid"]=1;      
         
         // attempt to authenticate user
         logon=call_aurora("doAuth",params,true,false);
      }
   }

   const resetCredentials = () => {
      // reset credentials      
      logonstarted=false;
      // checked=false;

      mode="";
      return "";
   }

   // redirect to a given route or main
   const redirect = (route) => {
      logonstarted=false;
      if ((route == undefined) || (route == "")) {          
         mode = "main";
      } else {                 
         mode = route;         
      }
   }

   const call_feide = () => {           
      // redirect to FEIDE auth
      window.location.href=CFG["oauth.script"];
      return "";
   }
</script>

<div class="ui_scroll">  
   <Privacy /> 
   <AuroraHeader/>      
   <StatusMessage/>
      {#if logonstarted}
         {#await logon}            
            <Status message="Logging in..." type="processing" />     
         {:then result}
            {#if result.err == 0}
               {#if redirecturl != ""} 
                  {redirect(redirecturl)}
               {:else}
                  {redirect("main")}
               {/if}
            {:else}
               {resetCredentials()}
            {/if}
         {:catch error}   
            <div></div>
         {/await}
      {:else}   
         {#if mode == ""}
            <div class="ui_center">
               <button class="ui_button" on:click={() => { call_feide(); }} disabled={disabled}>FEIDE Login</button>
            </div>
            <div class="ui_center">
               <div class="ui_label">Username</div>
               <div class="ui_input"><input type="text" bind:value="{username}" on:keypress={(e) => handleAuroraIdLogin(e) } name="username" id="username" size="64" maxlength="255" disabled={disabled}></div>
            </div>
            <div class="ui_center">
               <div class="ui_label">Password</div>
               <div class="ui_input"><input type="password" bind:value="{pw}" on:keypress={(e) => handleAuroraIdLogin(e) } name="password" id="password" size="64" maxlength="64" disabled={disabled}></div>
            </div>
            <div class="ui_center ui_margin_top"><button id="login" class="ui_button" on:click={() => handleAuroraIdLogin() } disabled={disabled}>Login</button></div>
            <Announcement />
         {:else}              
            <Main/>         
         {/if} 
      {/if}
      {#if disabled}           
         <FloatContent border={false}>
            <img width="90%" src={CFG["www.base"]+"/media/maintenance.png"} alt="System Maintenance">
         </FloatContent>
      {/if}
</div>
