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
// Description: Handles timedate data by converting between unixtime, javascript Date and ISO-8601.
//
// highest date in ms according to ECMA262
export const ECMA262_MAX_DATE = 8640000000000000;
export const ECMA262_MAX_DATE_SEC = Math.floor(ECMA262_MAX_DATE / 1000);

export function timezone () {
    return new Date().getTimezoneOffset();
}

export function timezoneStr (offset) {    
    if (offset == undefined) { offset=new Date().getTimezoneOffset(); }
    // check which type of offset
    let signed=false;
    if (offset < 0) { signed=true; offset=-1*offset }
    // convert offset to hours and minutes
    let hour=Math.floor(offset/60);
    let min=offset-(hour*60);
    // hours and minutes will never pass 24 and 60 respectively
    if (hour < 10) { hour="0"+hour; }
    if (min < 10) { min="0"+min; }
    // return result
    return (signed ? "+" : "-")+hour+":"+min;
}

export function date2ISO (date) {
    // if date is not defined, we use now-time
    if (date == undefined) { date=new Date(); }
    // get ms of date
    let ms=date.getTime();
    let tz=date.getTimezoneOffset()*60000;
    // check that we are not outside bounds when including timezone
    if ((ms - tz) > ECMA262_MAX_DATE) { date=new Date(ECMA262_MAX_DATE-(-1*tz)); }
    return new Date(date.getTime() - (date.getTimezoneOffset() * 60000 )).toISOString().split(/\.\d*Z/)[0]+timezoneStr(date.getTimezoneOffset());
}

export function ISO2Date (iso) {
    // if iso is not defined we use now-time
    if (iso == undefined) { iso=date2ISO(); }
    // parse iso string to date-instance and return it
    return new Date(Date.parse(String(iso)));
}

export function unixtime2ISO (time) {
    // if no time is defined, we use now-time    
    if (time == undefined) { time=date2Unixtime(); }    
    // convert unixtime to Date
    let date=unixtime2Date(time);
    // now let the date2ISO-function handle the rest
    return date2ISO(date);    
}

export function ISO2Unixtime (iso) {
    // first convert to Date-instace
    let date = ISO2Date(iso);
    // then convert date to unixtime
    return date2Unixtime(date);
}

export function date2Unixtime (date) {
    if (date == undefined) { date=new Date(); }
    // Date is in ms, while unixtime is in seconds, both have same epoch
    return Math.floor(date.getTime()/1000);
}

export function unixtime2Date (time) {
    if (time == undefined) { time=date2Unixtime(); }
    // if specified time is larger than max allowed date, set to max allowed    
    if (time > ECMA262_MAX_DATE_SEC) { time=ECMA262_MAX_DATE_SEC; }
    // ensure that time is not below zero, which is not allowed by unixtime
    if (time < 0) { time=0; }    
    // Unixtime is in sec, while Date is in ms, both have same epoch
    return new Date(time*1000);
}
