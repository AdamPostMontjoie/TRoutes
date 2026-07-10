# Lechmere -> Mass Ave July 8th Observations

**Route:** Lechmere to Mass Ave, with a transfer at North Station.

1. **Lechmere to Science Park:** I missed the train at Lechmere, and I was moved to "en route" to Science Park. However, I didn’t switch to "at stop" at Science Park ever, even when I checked on another app that the train was at North Station. I assume this is because Science Park is another surface stop. Alternatively, the platform might be too small, but I doubt it because of point #2.

2. **Science Park Entry (New Route):** Because of this bug, I created a new route, and set it to start at Science Park (I was still at Lechmere). It tracked entry to Science Park fine. However, I'm unsure what happened when we left as my memory is fuzzy. 

3. **North Station Arrival:** I can't remember if I had to manually set "en route" to North Station, I don't think I did. However, we never were set "at stop" at North Station, I had to do it manually. However, the transfer predictions did display properly. 

4. **Transfer Vehicle ID Handoff:** Failure of transfer vehicle ID handoff. This is likely because we never were set "at stop" at North Station, and the train went off of predictions before I manually triggered "at stop". 
- *Confirmed:* it tracked the train that came after successfully the one I took when it showed up.

5. **Back Bay / Mass Ave Tracking:** Switched to surface tracking once the train behind me entered Back Bay. This is a problem: Underground mode should only switch when we exit, as switching to next stop mode doesn't make sense like it does for surface. I was at the Mass Ave platform, but since it never was able to track us as leaving Back Bay, it was still trying to check that.

---

### UI Bugs
6. **Start Button Issue:** One time, the Start button triggered tracking but not the display. I believe this was once I had already started and canceled a route. Triggered multiple "started tracking" notifications. Reconciliation actually fixed this.

### Musings
7. **Thoughts for Improvement:**
- Perhaps we can keep a hold of trains before and after us for better tracking? 
- And do a similar queuing for transfer trains? 
- I think 45 seconds is too quick, and we shouldn't dump the train in a rigid timeframe anyway. 
- I am also surprised the location didn't... *(thought cut off)*
