import React from "react";
import {
  Mod,
  ModalContent,
  ModalHeader,
  ModalBody,
  ModalFooter,
  InputFeild,
  InputImage,
  InputContainer,
  CloseButton,
} from "./ModalElements";

import {
   H4Text
} from "../Components"

const Modal = (props) => {
  if (!props.show) {
    return null
  }

  return (
    <Mod>
      <ModalContent>
        <ModalHeader>
          <H4Text white style={{'paddingLeft':'85px', 'paddingRight':'55px'}}>Connect Wallet</H4Text>
          <CloseButton onClick={props.onClose}>
            <svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
              <rect width="48" height="48" rx="24" fill="#252727"/>
              <path d="M19 19L29 29" stroke="#EDF0EB" stroke-width="2"/>
              <path d="M19 29L29 19" stroke="#EDF0EB" stroke-width="2"/>
            </svg>
          </CloseButton>
        </ModalHeader>
        <ModalBody>
          <InputContainer>
            <InputFeild type="text" placeholder="Metamask">
            </InputFeild>
            <InputImage>
              <svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
                <circle cx="24" cy="24" r="24" fill="#EC7B3B"/>
              </svg>
            </InputImage>
          </InputContainer>
          <InputContainer>
            <InputFeild type="text" placeholder="Metamask">
            </InputFeild>
            <InputImage>
              <svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
                <circle cx="24" cy="24" r="24" fill="#00A3FF"/>
              </svg>
            </InputImage>
          </InputContainer>
          <InputContainer>
            <InputFeild type="text" placeholder="Metamask">
            </InputFeild>
            <InputImage>
              <svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
                <circle cx="24" cy="24" r="24" fill="#C4C4C4"/>
              </svg>
            </InputImage>
          </InputContainer>
            <InputContainer>
            <InputFeild type="text" placeholder="Metamask">
            </InputFeild>
            <InputImage>
              <svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
                <circle cx="24" cy="24" r="24" fill="#C4C4C4"/>
              </svg>
            </InputImage>
          </InputContainer>
        </ModalBody>
        <ModalFooter>
          What are these?
        </ModalFooter>
      </ModalContent>
    </Mod>
  )
}

export default Modal; 