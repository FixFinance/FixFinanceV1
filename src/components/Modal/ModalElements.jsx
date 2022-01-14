import styled from "styled-components";

export const Mod = styled.div`
  position: fixed;
  left: 0;
  top: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
`

export const ModalContent = styled.div`
  width: 466px;
  height: 512px;
  background-color: #191A1A;
  border-radius: 20px;
`

export const ModalHeader = styled.div`
  display: flex;
  padding: 20px 10px;
  margin: 0;
`

export const ModalBody = styled.div`
  padding: 10px;
  display: flex;
  align-items: center;
  flex-direction: column;
`

export const ModalFooter = styled.div`
  padding-top: 30px;
  color: #929095;
  text-align: center;
`

export const InputFeild = styled.input`
  width: 386px;
  height: 66px;
  border-radius: 90px;
  background-color: #252727;
  margin-top: 14px;
  padding-left: 40px;
  border: none;
  font-size: 14px;
  color: white;
  &:focus {
    outline: none;
  }
`

export const InputImage = styled.div`
  position:absolute;
  bottom:8px;
  right: 15px;
`

export const InputContainer = styled.div`
  position:relative;
  padding:0;
  margin:0;
`

export const CloseButton = styled.button`
  border: none;
  outline: none;
  text-decoration: none;
  cursor: pointer;
  background-color: rgba(0,0,0,0);
  padding: 0;
` 