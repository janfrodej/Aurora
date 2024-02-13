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
// getCookie-function gracefully stolen from www.w3schools.com
export function getCookie(cname) {
    let name = cname + "=";
    //let decodedCookie = decodeURIComponent(document.cookie);
    let decodedCookie = document.cookie;
    let ca = decodedCookie.split(';');
    for(let i = 0; i <ca.length; i++) {
      let c = ca[i];
      while (c.charAt(0) == ' ') {
        c = c.substring(1);
      }
      if (c.indexOf(name) == 0) {
        return c.substring(name.length, c.length);
      }
    }
    return "";
  }

  // retrieve sub-value of a cookie
  export function getCookieValue(cname,vname) {
    let ch = getCookieValues (cname);
    if (ch != undefined) {
      // we successfully retrieved hash object of cookie - check for value
      let val = (ch[vname] == undefined ? "" : ch[vname]);
      // cookie values are uri-encoded sometimes and that is not acceptable to 
      // the atob-function.
      val = decodeURIComponent(val);
      // ensure friendly cookie with valid base64
      // characters before attempting to decode it
      if (/^[a-zA-Z\+\/\=]+/.test(val)) {
        // even with valid characters we approach
        // the conversion with caution       
        try {
          val = window.atob(val);
        } catch {
          // do nothing if it fails - just continue...
        }
      }  
      if (vname in ch) { return val; } // value exists
      else { return ""; } // value does not exist
    } else {
      return ""; // cookie does not exist
    }
  }

  // set/update a value of a cookie
  export function setCookieValue(cname,vname,value,domain,maxage,path,samesite,secure) {
    // get hash of cookie values
    let ch = getCookieValues(cname);
    // define hash if it does not exist/undefined
    if (ch == undefined) { ch = {}; }

    // set cookie value
    ch[vname] = window.btoa(value);
    // make cookie string from cookie hash
    let cstr = createCookie(cname,ch,domain,maxage,path,samesite,secure);   
    // success
    return true;    
  }

  // get all values in a cookie as a hash object
  export function getCookieValues (cname) {
    // get cookie itself
    let c = getCookie(cname);
    if (c != "") {
      // we retrieved the cookie, now get the sub-values
      // read string and split on "&"-sign
      let vals = c.split("&");
      // go through each subvalue
      let ch={};
      for (let i=0; i < vals.length; i=i+2) {        
        let name = vals[i];
        let val = (vals.length > i+1 ? vals[i+1] : "");        
        ch[name] = val;
      }
      // return hash object with all values
      return ch;
    } else { return undefined; }
  }

  // create cookiestring from a hash object
  // optionally also set domain, max-age and so on.
  // this method also saves the newly created cookie
  export function createCookie (name,h,domain,maxage,path,samesite,secure) {
    let s = name+"=";
    let first = true;
    for (let key in h) {
      // add hash key to cookie string
      s = (first ? s+key+"&"+h[key] : s+"&"+key+"&"+h[key]);
      // set first to false
      if (first) { first = false; }
    }
    // add end of values
    s = s + ";";
    // add domain
    s = (domain != undefined ? s+" Domain="+domain+";" : s+" Domain=localhost;");
    // add max-age (max-age in secs has precedence over expires)
    // default to a whole day
    maxage = (maxage != undefined ? Number(maxage) : 86400);
    s = s+" Max-Age="+maxage+";";
    // add path
    s = (path != undefined ? s+" Path="+path+";" : s+" Path=/;");
    // add samesite
    samesite = (samesite != undefined ? samesite : "Lax");
    if ((String(samesite).toLowerCase() != "lax") &&
        (String(samesite).toLowerCase() != "strict") &&
        (String(samesite).toLowerCase() != "none")) {
          samesite = "Lax";
        }        
    s = s + " SameSite="+samesite+";";
    if (String(samesite).toLowerCase() == "none") {
      // none requires the secure-setting to be set
      s = s + " Secure;";
    }
    // add secure, ensure we do not set it twice
    if ((secure) && (String(samesite).toLowerCase() != "none")) {
      s = s + " Secure;";
    }
    // set the cookie in the document
    document.cookie = s;
    // return the result
    return s;
  }

  // delete a named cookie
  export function deleteCookie(cname) {
    let ch = getCookieValues(cname);
    if (ch != undefined) {
      // create string of cookie to delete
      // set maxage to minus value to have it removed
      let cstr = createCookie(cname,ch,undefined,-1);
      // delete cookie by setting new string in document
      document.cookie = cstr;
      // success
      return true;
    } else {
      // failed
      return false;
    }
  }

  // transform value into a number
  export function string2Number(value,def) {
    if ((value != undefined) && (value != "")) {
      // this is a valid string, transform it into a number
      return Number(value);
    } else {
      // this is not a valid value, return default (and ensure typecast there too)
      return Number(def);      
    }
  }

  // transform value into a boolean
  export function string2Boolean(value,def) {
    if ((value != undefined) && (value != "")) {
      // this is a valid string, transform it into a boolean
      // if it is not true, it must be false
      return (String(value).toLowerCase() == "true" ? true : false);
    } else {
      // this is not a valid value, return default (and ensure typecast there too)
      return (def == true || String(def).toLowerCase() == "true" ? true : false);
    }
  }
