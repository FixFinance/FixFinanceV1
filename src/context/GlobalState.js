import React, { createContext, useReducer } from 'react';
import AppReducer from './AppReducer';

// TODO: delete all the template states & actions
const initialState = {
   shoppingList : [],
   NGBwrapperAddr: '0xBE5115D20ccdf5c041A27030FB3eAbd86C384579',
   FixCapitalPoolAddr: '0xD12C5387108e4B75579f2EE3688eC4cD014A6E4A',
   OrderbookExchangeAddr: '0xc4ACaAc6B7F6cA1245F0a70F13C7C0836Dd82494'
}

export const GlobalContext = createContext(initialState);

// source: https://endertech.com/blog/using-reacts-context-api-for-global-state-management
export const GlobalProvider = ({ children }) => {
   const [state, dispatch] = useReducer(AppReducer, initialState);

   // Actions for changing state

   function addItemToList(item) {
       dispatch({
           type: 'ADD_ITEM',
           payload: item
       });
   }

   function removeItemFromList(item) {
       dispatch({
           type: 'REMOVE_ITEM',
           payload: item
       });
   }

   return(
      <GlobalContext.Provider value = {{shoppingList : state.shoppingList, addItemToList, removeItemFromList}}> 
        {children} 
   </GlobalContext.Provider>
   )
}