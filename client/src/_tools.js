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
// Description: Utility functions of AURORA such as sorting arrays and into arrays, conversion and sending application messages and more.
//
// exported functions. variables and constants
//
// hash2Array(hash)
// hash2SortedArray (hash,level=1,dir=1,orderby,lexical=true) 
// hash2SortedSelect (hash,sortby,dir,lexical=true)
// sortArray (arr,dir=1,lexical=true)
// sortArrayOfArray (arr,dir=1,orderby=0,lexical=true)
// int2SI (value)
// sendStatusMessage (msg,level)
// SYSINFO - hash-object with various system info
//

export function hash2Array (hash) {
    let result=[];   

    // put hash into an array
    for (let h in hash) {
       result.push([h,hash[h]]);
    }  

    return result;
}


// convert a numbered hash into an array ordered by the same numbers
export function numberedHash2Array (hash) {
   let result=hash2Array(hash);
   
   result.sort(function (a,b) {
      let res=0;
      
      // check if hash keys in array is numerically larger or not than each other
      res=(Number(a[0]) > Number(b[0]) ? 1: -1);
      res=(Number(a[0]) == Number(b[0]) ? 0: res);

      return res;
   });

   return result;
}

// level is the hash-level, 0 is the upper part, 1 is the one sublevel below and so on
// dir > 0 = asc, 0 = no sort, < 0 = desc
// orderby is the level-key name to sort by
// lexical defines if the comparison is to be done on textual values or numbers
export function hash2SortedArray (hash,level=1,dir=1,orderby,lexical=true) {
  let result=hash2Array(hash);

  // sort the array  
  result.sort(function (a,b) {      
    if (dir == 0) { return 0; } // no sorting
    let res=0;
    // check if user has specified sublevel key to sort on or not.
    if (orderby != undefined) {
      if (lexical) {
         res=(""+a[level][orderby].toUpperCase()).localeCompare(b[level][orderby].toUpperCase(),undefined, { sensitivity: 'base' });    
      } else {         
         res=(Number(a[level][orderby]) > Number(b[level][orderby]) ? 1 : -1);           
         res=(Number(a[level][orderby]) == Number(b[level][orderby]) ? 0 : res);
      }      
    } else {
      if (lexical) {
         res=(""+a[level].toUpperCase()).localeCompare(b[level].toUpperCase(),undefined, { sensitivity: 'base' });    
      } else {
         res=(Number(a[level]) > Number(b[level]) ? 1: -1);         
         res=(Number(a[level]) == Number(b[level]) ? 0: res);
      }
    }
    if (dir < 0) { res=-res; } // invert result if descending
    return res;
  });

  return result;
}

export function hash2SortedSelect (hash,sortby,dir,lexical=true) {
   // sort first
   let arr=hash2SortedArray(hash,sortby,dir,undefined,lexical);
   // remake the array to a array with hashes
   let res=[];
   arr.map (function (v,i,a) {
      res.push({ id: v[0], text: v[1] });
   });

   return res;
}

// sort an array
export function sortArray (arr,dir=1,lexical=true) {
   // if not array, just return input as-is
   if (!Array.isArray(arr)) { return arr; }
   arr.sort(function (a,b) { 
      if (dir == 0) { return 0; } // no sorting
      let res=0;
      if (lexical) {
           res=(""+a.toUpperCase()).localeCompare(b.toUpperCase(),undefined, { sensitivity: 'base' });    
      } else {         
         res=(Number(a) > Number(b) ? 1 : -1);           
         res=(Number(a) == Number(b) ? 0 : res);
      }                   
      if (dir < 0) { res=-res; } // invert result if descending
      return res;
    });
    // return sorted array
    return arr;
};

// sort an array of array, two-dimensional array
// specify orderby index on the sublevel array to sort it by.
export function sortArrayOfArray (arr,dir=1,orderby=0,lexical=true) {
   // if not array, just return input as-is
   if (!Array.isArray(arr)) { return arr; }
   // check that direction is sensible
   if ((dir < -1) || (dir > 1)) { return arr; } 
   // orderby must specify index of sub-array to order by
   // if none is specified it default to 0, or first element of sub-array
   if (typeof orderby != "number") { return arr; }
   // check that orderby is not too low
   // we cannot index value of an array below zero
   if (orderby < 0) { return arr; } 
   // sort the array  
   arr.sort(function (a,b) {      
      if (dir == 0) { return 0; } // no sorting
      // check that sublevel array exists
      if ((!Array.isArray(a)) || (!Array.isArray(b))) { return 0; } // keep as is
      // check that orderby is not out of bounds for a- and b-subarray
      if ((orderby >= a.length) || (orderby >= b.length)) { return 0; } // keep as is
      let res=0;
      // check what type of sort has been selected, lexical or numerical
      if (lexical) {
         res=(""+a[orderby].toUpperCase()).localeCompare(b[orderby].toUpperCase(),undefined, { sensitivity: 'base' });    
      } else {
         res=(Number(a[orderby]) > Number(b[orderby]) ? 1: -1);         
         res=(Number(a[orderby]) == Number(b[orderby]) ? 0: res);
      }     
      if (dir < 0) { res=-res; } // invert result if descending
      return res;
   });
 
   return arr;
 }
 
// convert byte integer to correct SI unit
export function int2SI (value) {
   value=(value != undefined && /^\d+$/.test(value) ? value : 0);
   let index=Math.floor(Math.log(value||1)/Math.log(1000));
   index=(index < 0 ? 0 : index);
   let units=["B","KB","MB","GB","TB","PB","EB"];
   let u=units[index];
   let fl=value/1000**index;
   return ""+fl.toFixed(1)+u;
}

// convert SI-unit to correct byte integer
export function SI2Int (value) {
   if (value == undefined) { return 0; }
   let match = value.match(/^(\d+)(\w+)$/);
   let val = (match != undefined && match[1] != undefined ? Math.floor(match[1]) : 0);
   // get the unit
   let unit = (match != undefined && match[2] != undefined ? String(match[2]).toUpperCase() : "B");
   // we do not accept negative values - convert to positive
   if (val < 0) { val = val*-1; }
   // allow both single and double unit designations
   let units;
   if (String(unit).length == 1) {
      units=["K","M","G","T","P","E"];
   } else {
      units=["KB","MB","GB","TB","PB","EB"];
   }
   let pos=units.indexOf(unit);
   if (pos > -1) {
      // unit was found - let figure out the multiplier
      let multi=1000**(pos+1);
      // we have the multiplier for the value - return the byte equivalent
      return (multi > 0 ? val*multi : val);
   } else {
      // we did not find the SI-unit type - return value as is
      return val;
   }
}

// this function enables the application to send 
// a message to the screen of the user. The event 
// is caught by the StatusMessage.svelte component
export function sendStatusMessage (msg,level) {
   // create event object
   const errorEvent = new Event('statusmessage', {
                           bubbles: true,
                           cancelable: true,
                           composed: false
                        });
   // add status message to event 
   errorEvent.message=msg;
   // set status message level (undefined = error)
   errorEvent.level=level;
   // add element that triggers event
   let elem = document.createElement("div");
   document.body.appendChild(elem);
   // dispatch errormessage on a div in document
   elem.dispatchEvent(errorEvent);
   // remove element
   elem.remove();
};

// get some sysinfo
const getInfo = () => {
    let info={};
    for (let key in navigator) {
        if ((Array.isArray(navigator[key])) ||
            (typeof navigator[key] == "string")) {
            info[key] = navigator[key];
        }
    }
    return info;
}

export const SYSINFO = getInfo();
