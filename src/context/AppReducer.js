import React from 'react';
 
// source: https://endertech.com/blog/using-reacts-context-api-for-global-state-management
export default (state, action) => {
   switch(action.type) {
       case 'ADD_ITEM':
           return {
                   shoppingList: [action.payload, ...state.shoppingList]
           }
       case 'REMOVE_ITEM':
           return {
               shoppingList: state.shoppingList.filter(item => item !== action.payload)
           }
       default:
           return state;
   }
}